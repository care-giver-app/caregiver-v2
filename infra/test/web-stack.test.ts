import * as cdk from 'aws-cdk-lib';
import { Match, Template } from 'aws-cdk-lib/assertions';
import { WebStack } from '../lib/web-stack';

function synth(stage: 'dev' | 'prod') {
  const app = new cdk.App({
    context: {
      // HostedZone.fromLookup needs a cached answer to synth without AWS.
      'hosted-zone:account=123456789012:domainName=caretosher.com:region=us-east-1': {
        Id: '/hostedzone/Z0TEST',
        Name: 'caretosher.com.',
      },
    },
  });
  const stack = new WebStack(app, `Caregiver${stage === 'prod' ? 'Prod' : 'Dev'}-Web`, {
    env: { account: '123456789012', region: 'us-east-1' },
    stage,
  });
  return Template.fromStack(stack);
}

describe('WebStack', () => {
  test.each([
    ['prod', 'caretosher.com'],
    ['dev', 'dev.caretosher.com'],
  ] as const)('%s serves %s and its www over HTTPS', (stage, domain) => {
    const t = synth(stage);
    t.hasResourceProperties('AWS::CloudFront::Distribution', {
      DistributionConfig: Match.objectLike({
        Aliases: [domain, `www.${domain}`],
        DefaultCacheBehavior: Match.objectLike({ ViewerProtocolPolicy: 'redirect-to-https' }),
      }),
    });
    t.hasResourceProperties('AWS::CertificateManager::Certificate', {
      DomainName: domain,
      SubjectAlternativeNames: [`www.${domain}`],
    });
    t.resourceCountIs('AWS::Route53::RecordSet', 4); // A + AAAA for the domain and www
  });

  test('the bucket is private and only CloudFront reads it', () => {
    const t = synth('prod');
    t.hasResourceProperties('AWS::S3::Bucket', {
      PublicAccessBlockConfiguration: {
        BlockPublicAcls: true,
        BlockPublicPolicy: true,
        IgnorePublicAcls: true,
        RestrictPublicBuckets: true,
      },
    });
    t.resourceCountIs('AWS::CloudFront::OriginAccessControl', 1);
  });
});
