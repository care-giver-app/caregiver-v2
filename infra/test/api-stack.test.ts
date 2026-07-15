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
          LOG_LEVEL: 'debug',
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

  test('wires a v2-specific custom domain with a DNS-validated cert and alias record', () => {
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
    // Dev uses api-v2-dev (NOT v1's api-dev), with a DNS-validated regional cert.
    template.hasResourceProperties('AWS::CertificateManager::Certificate', {
      DomainName: 'api-v2-dev.caretosher.com',
      ValidationMethod: 'DNS',
    });
    template.hasResourceProperties('AWS::ApiGatewayV2::DomainName', {
      DomainName: 'api-v2-dev.caretosher.com',
    });
    template.resourceCountIs('AWS::ApiGatewayV2::ApiMapping', 1);
    template.hasResourceProperties('AWS::Route53::RecordSet', {
      Name: 'api-v2-dev.caretosher.com.',
      Type: 'A',
    });
  });

  test('prod uses api-v2 (the canonical name is reserved for the v1 cutover)', () => {
    const app = new cdk.App();
    const env = { account: '123456789012', region: 'us-east-2' };
    const shared = new SharedStack(app, 'CaregiverProd-Shared', { env, stage: 'prod' });
    const stack = new ApiStack(app, 'CaregiverProd-Api', {
      env,
      stage: 'prod',
      version: '0.0.0-test',
      appConfigApplicationId: 'app-test',
      appConfigEnvironmentId: 'env-test',
      appConfigProfileId: 'profile-test',
      userPool: shared.userPool,
      userPoolClient: shared.userPoolClient,
      tables: shared.tables,
    });
    const template = Template.fromStack(stack);
    template.hasResourceProperties('AWS::ApiGatewayV2::DomainName', {
      DomainName: 'api-v2.caretosher.com',
    });
    template.hasResourceProperties('AWS::Lambda::Function', {
      Environment: {
        Variables: Match.objectLike({ LOG_LEVEL: 'info' }),
      },
    });
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
    t.resourceCountIs('AWS::ApiGatewayV2::Route', 31);

    for (const routeKey of [
      'GET /me',
      'POST /care-groups',
      'GET /care-groups/{careGroupId}/members',
      'POST /care-groups/{careGroupId}/invitations',
      'DELETE /care-groups/{careGroupId}/invitations/{token}',
      'GET /invitations/mine',
      'POST /invitations/{token}/accept',
      'GET /receivers',
      'POST /trackers/{trackerId}/events',
      'GET /tracker-templates',
      'GET /trackers/{trackerId}/scheduled-items',
      'POST /trackers/{trackerId}/scheduled-items',
      'GET /receivers/{receiverId}/scheduled-items',
      'GET /scheduled-items/{scheduledItemId}',
      'PUT /scheduled-items/{scheduledItemId}',
      'DELETE /scheduled-items/{scheduledItemId}',
    ]) {
      t.hasResourceProperties('AWS::ApiGatewayV2::Route', {
        RouteKey: routeKey,
        AuthorizationType: 'JWT',
      });
    }
    for (const routeKey of ['GET /health', 'GET /flags']) {
      t.hasResourceProperties('AWS::ApiGatewayV2::Route', {
        RouteKey: routeKey,
        AuthorizationType: 'NONE',
      });
    }
  });
});
