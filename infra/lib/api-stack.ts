import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigw from 'aws-cdk-lib/aws-apigatewayv2';
import * as integ from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as path from 'node:path';
import { execSync } from 'node:child_process';
import type { Stage } from './shared-stack';

export interface ApiStackProps extends cdk.StackProps {
  stage: Stage;
  version: string;
}

export class ApiStack extends cdk.Stack {
  public readonly apiFunction: lambda.Function;

  constructor(scope: Construct, id: string, props: ApiStackProps) {
    super(scope, id, props);

    const apiRoot = path.resolve(__dirname, '..', '..', 'api');
    const bootstrapDir = path.resolve(apiRoot, 'cmd', 'lambda');

    // Build the Go Lambda binary at synth time.
    execSync(
      'GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -tags lambda.norpc -o bootstrap ./...',
      { cwd: bootstrapDir, stdio: 'inherit' },
    );

    const logGroup = new logs.LogGroup(this, 'ApiFunctionLogs', {
      logGroupName: `/aws/lambda/caregiver-${props.stage}-api`,
      retention:
        props.stage === 'prod' ? logs.RetentionDays.ONE_MONTH : logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    this.apiFunction = new lambda.Function(this, 'ApiFunction', {
      runtime: lambda.Runtime.PROVIDED_AL2023,
      architecture: lambda.Architecture.ARM_64,
      handler: 'bootstrap',
      code: lambda.Code.fromAsset(bootstrapDir, {
        exclude: ['*.go', '*.mod', '*.sum'],
      }),
      memorySize: 256,
      timeout: cdk.Duration.seconds(10),
      tracing: lambda.Tracing.ACTIVE,
      environment: {
        SERVICE: 'api',
        STAGE: props.stage,
        APP_VERSION: props.version,
      },
      logGroup,
    });

    const httpApi = new apigw.HttpApi(this, 'HttpApi', {
      apiName: `caregiver-${props.stage}-api`,
    });

    httpApi.addRoutes({
      path: '/health',
      methods: [apigw.HttpMethod.GET],
      integration: new integ.HttpLambdaIntegration('HealthIntegration', this.apiFunction),
    });

    new cdk.CfnOutput(this, 'HttpApiUrl', { value: httpApi.apiEndpoint });
  }
}
