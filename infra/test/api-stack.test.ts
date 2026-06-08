import * as cdk from 'aws-cdk-lib';
import { Match, Template } from 'aws-cdk-lib/assertions';
import { ApiStack } from '../lib/api-stack';

describe('ApiStack', () => {
  test('creates a Lambda function and HTTP API', () => {
    const app = new cdk.App();
    const stack = new ApiStack(app, 'TestApi', {
      env: { account: '123456789012', region: 'us-east-2' },
      stage: 'dev',
      version: '0.0.0-test',
      appConfigApplicationId: 'app-test',
      appConfigEnvironmentId: 'env-test',
      appConfigProfileId: 'profile-test',
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
    template.resourceCountIs('AWS::ApiGatewayV2::Route', 1);
  });
});
