import * as cdk from 'aws-cdk-lib';
import { Match, Template } from 'aws-cdk-lib/assertions';
import { ApiStack } from '../lib/api-stack';
import { SharedStack } from '../lib/shared-stack';

describe('ApiStack', () => {
  test('creates a Lambda function and HTTP API', () => {
    const app = new cdk.App();
    const env = { account: '123456789012', region: 'us-east-2' };
    const shared = new SharedStack(app, 'CaregiverDev-Shared', { env, stage: 'dev' });
    const stack = new ApiStack(app, 'CaregiverDev-Api', {
      env,
      stage: 'dev',
      version: '0.0.0-test',
      appConfigApplicationId: 'app-test',
      appConfigEnvironmentId: 'env-test',
      appConfigProfileId: 'profile-test',
      userPool: shared.userPool,
      userPoolClient: shared.userPoolClient,
      tables: shared.tables,
    });
    const template = Template.fromStack(stack);
    template.hasResourceProperties('AWS::Lambda::Function', {
      Runtime: 'provided.al2023',
      Architectures: ['arm64'],
      TracingConfig: { Mode: 'Active' },
    });
    template.hasResourceProperties('AWS::Lambda::Function', {
      Layers: Match.arrayWith([Match.stringLikeRegexp('AWS-AppConfig-Extension')]),
      Environment: {
        Variables: Match.objectLike({
          APPCONFIG_APPLICATION_ID: 'app-test',
          APPCONFIG_ENVIRONMENT_ID: 'env-test',
          APPCONFIG_PROFILE_ID: 'profile-test',
        }),
      },
    });
    template.hasResourceProperties('AWS::IAM::Policy', {
      PolicyDocument: Match.objectLike({
        Statement: Match.arrayWith([
          Match.objectLike({
            Action: Match.arrayWith([
              'appconfig:GetLatestConfiguration',
              'appconfig:StartConfigurationSession',
            ]),
          }),
        ]),
      }),
    });
    template.resourceCountIs('AWS::ApiGatewayV2::Api', 1);
    template.hasResourceProperties('AWS::ApiGatewayV2::Route', { RouteKey: 'GET /health' });
    template.hasResourceProperties('AWS::ApiGatewayV2::Route', { RouteKey: 'GET /flags' });
  });

  test('api stack wires a JWT authorizer and authed routes', () => {
    const app = new cdk.App();
    const env = { account: '123456789012', region: 'us-east-2' };
    const shared = new SharedStack(app, 'CaregiverDev-Shared', { env, stage: 'dev' });
    const apiStack = new ApiStack(app, 'CaregiverDev-Api', {
      env,
      stage: 'dev',
      version: '0.0.0',
      appConfigApplicationId: 'app',
      appConfigEnvironmentId: 'envid',
      appConfigProfileId: 'prof',
      userPool: shared.userPool,
      userPoolClient: shared.userPoolClient,
      tables: shared.tables,
    });
    const t = Template.fromStack(apiStack);
    t.resourceCountIs('AWS::ApiGatewayV2::Authorizer', 1);
    t.hasResourceProperties('AWS::ApiGatewayV2::Authorizer', { AuthorizerType: 'JWT' });
    t.resourceCountIs('AWS::ApiGatewayV2::Route', 8);
  });
});
