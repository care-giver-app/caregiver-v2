import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { SharedStack } from '../lib/shared-stack';

describe('SharedStack', () => {
  test('dev stack creates an SNS topic for alarms', () => {
    const app = new cdk.App();
    const stack = new SharedStack(app, 'TestShared', {
      env: { account: '123456789012', region: 'us-east-1' },
      stage: 'dev',
    });
    const template = Template.fromStack(stack);
    template.hasResourceProperties('AWS::SNS::Topic', {
      DisplayName: 'Caregiver Dev Alarms',
    });
  });

  test('prod stack uses prod alarm topic name', () => {
    const app = new cdk.App();
    const stack = new SharedStack(app, 'TestSharedProd', {
      env: { account: '123456789012', region: 'us-east-1' },
      stage: 'prod',
    });
    const template = Template.fromStack(stack);
    template.hasResourceProperties('AWS::SNS::Topic', {
      DisplayName: 'Caregiver Prod Alarms',
    });
  });

  test('creates AppConfig application + profile + deployment', () => {
    const app = new cdk.App();
    const stack = new SharedStack(app, 'TestSharedAC', {
      env: { account: '123456789012', region: 'us-east-1' },
      stage: 'dev',
    });
    const template = Template.fromStack(stack);
    template.resourceCountIs('AWS::AppConfig::Application', 1);
    template.resourceCountIs('AWS::AppConfig::ConfigurationProfile', 1);
    template.resourceCountIs('AWS::AppConfig::Environment', 1);
    template.resourceCountIs('AWS::AppConfig::HostedConfigurationVersion', 1);
    template.resourceCountIs('AWS::AppConfig::DeploymentStrategy', 1);
    template.resourceCountIs('AWS::AppConfig::Deployment', 1);
  });

  test('shared stack creates the four B1 tables with prefixed names', () => {
    const app = new cdk.App();
    const stack = new SharedStack(app, 'CaregiverDev-Shared', {
      env: { account: '123456789012', region: 'us-east-2' },
      stage: 'dev',
    });
    const t = Template.fromStack(stack);
    t.resourceCountIs('AWS::DynamoDB::Table', 4);
    for (const name of [
      'caregiver-dev-user',
      'caregiver-dev-care-group',
      'caregiver-dev-membership',
      'caregiver-dev-invitation',
    ]) {
      t.hasResourceProperties('AWS::DynamoDB::Table', { TableName: name });
    }
  });

  test('invitation table has a TTL on expires_at', () => {
    const app = new cdk.App();
    const stack = new SharedStack(app, 'CaregiverDev-Shared2', {
      env: { account: '123456789012', region: 'us-east-2' },
      stage: 'dev',
    });
    Template.fromStack(stack).hasResourceProperties('AWS::DynamoDB::Table', {
      TableName: 'caregiver-dev-invitation',
      TimeToLiveSpecification: { AttributeName: 'expires_at', Enabled: true },
    });
  });

  test('shared stack creates a Cognito user pool + app client', () => {
    const app = new cdk.App();
    const stack = new SharedStack(app, 'CaregiverDev-Shared3', {
      env: { account: '123456789012', region: 'us-east-2' },
      stage: 'dev',
    });
    const t = Template.fromStack(stack);
    t.hasResourceProperties('AWS::Cognito::UserPool', { UserPoolName: 'caregiver-dev' });
    t.resourceCountIs('AWS::Cognito::UserPoolClient', 1);
  });
});
