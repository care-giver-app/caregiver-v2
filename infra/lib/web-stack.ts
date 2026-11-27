import * as path from 'path';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as acm from 'aws-cdk-lib/aws-certificatemanager';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as route53Targets from 'aws-cdk-lib/aws-route53-targets';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import type { Stage } from './shared-stack';

export interface WebStackProps extends cdk.StackProps {
  stage: Stage;
}

/**
 * The website at caretosher.com (prod) and dev.caretosher.com (dev): for now only the pages the
 * app and the App Store link to (privacy, terms, support), served from web/site.
 *
 * This stack MUST be in us-east-1: CloudFront only accepts certificates from there, and keeping
 * the whole stack beside its certificate avoids cross-region references.
 */
export class WebStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: WebStackProps) {
    super(scope, id, props);

    const rootDomain = 'caretosher.com';
    const siteDomain = props.stage === 'prod' ? rootDomain : `dev.${rootDomain}`;
    const domainNames = [siteDomain, `www.${siteDomain}`];

    const zone = route53.HostedZone.fromLookup(this, 'HostedZone', { domainName: rootDomain });

    const certificate = new acm.Certificate(this, 'SiteCertificate', {
      domainName: siteDomain,
      subjectAlternativeNames: [`www.${siteDomain}`],
      validation: acm.CertificateValidation.fromDns(zone),
    });

    // Private: only CloudFront reads it (origin access control). Its contents are rebuilt from
    // web/site on every deploy, so nothing in it needs to survive the stack.
    const bucket = new s3.Bucket(this, 'SiteBucket', {
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // S3 has no directory index behind CloudFront, so /privacy and /privacy/ serve
    // privacy/index.html, and www redirects to the bare domain.
    const rewrite = new cloudfront.Function(this, 'SiteRewrite', {
      runtime: cloudfront.FunctionRuntime.JS_2_0,
      code: cloudfront.FunctionCode.fromInline(`
function handler(event) {
  var req = event.request;
  var host = req.headers.host && req.headers.host.value;
  if (host && host.indexOf('www.') === 0) {
    return {
      statusCode: 301,
      statusDescription: 'Moved Permanently',
      headers: { location: { value: 'https://' + host.slice(4) + req.uri } },
    };
  }
  if (req.uri.endsWith('/')) {
    req.uri += 'index.html';
  } else if (req.uri.lastIndexOf('.') < req.uri.lastIndexOf('/') + 1) {
    req.uri += '/index.html';
  }
  return req;
}`),
    });

    const distribution = new cloudfront.Distribution(this, 'SiteDistribution', {
      domainNames,
      certificate,
      defaultRootObject: 'index.html',
      priceClass: cloudfront.PriceClass.PRICE_CLASS_100,
      defaultBehavior: {
        origin: origins.S3BucketOrigin.withOriginAccessControl(bucket),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
        responseHeadersPolicy: cloudfront.ResponseHeadersPolicy.SECURITY_HEADERS,
        functionAssociations: [
          { function: rewrite, eventType: cloudfront.FunctionEventType.VIEWER_REQUEST },
        ],
      },
      errorResponses: [
        // Missing keys come back from a private bucket as 403; show the 404 page instead.
        { httpStatus: 403, responseHttpStatus: 404, responsePagePath: '/404.html' },
        { httpStatus: 404, responseHttpStatus: 404, responsePagePath: '/404.html' },
      ],
    });

    new s3deploy.BucketDeployment(this, 'SiteDeployment', {
      sources: [s3deploy.Source.asset(path.join(__dirname, '../../web/site'))],
      destinationBucket: bucket,
      distribution,
      distributionPaths: ['/*'],
    });

    const target = route53.RecordTarget.fromAlias(
      new route53Targets.CloudFrontTarget(distribution),
    );
    domainNames.forEach((name, i) => {
      const id = i === 0 ? 'Apex' : 'Www';
      new route53.ARecord(this, `${id}A`, { zone, recordName: name, target });
      new route53.AaaaRecord(this, `${id}Aaaa`, { zone, recordName: name, target });
    });

    new cdk.CfnOutput(this, 'SiteUrl', { value: `https://${siteDomain}` });
  }
}
