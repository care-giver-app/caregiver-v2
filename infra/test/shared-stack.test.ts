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

  test('shared stack creates the B1+B3a tables with prefixed names', () => {
    const app = new cdk.App();
    const stack = new SharedStack(app, 'CaregiverDev-Shared', {
      env: { account: '123456789012', region: 'us-east-2' },
      stage: 'dev',
    });
    const t = Template.fromStack(stack);
    t.resourceCountIs('AWS::DynamoDB::Table', 8 + 13);
    for (const name of [
      'caregiver-dev-user',
      'caregiver-dev-care-group',
      'caregiver-dev-membership',
      'caregiver-dev-invitation',
      'caregiver-dev-receiver',
      'caregiver-dev-tracker',
      'caregiver-dev-event',
      'caregiver-dev-scheduled-item',
    ]) {
      t.hasResourceProperties('AWS::DynamoDB::Table', { TableName: name });
    }
  });

  test('shared stack creates the ADR 0012 tables with a v1- prefix', () => {
    const app = new cdk.App();
    const stack = new SharedStack(app, 'CaregiverDev-SharedV1', {
      env: { account: '123456789012', region: 'us-east-2' },
      stage: 'dev',
    });
    const t = Template.fromStack(stack);
    for (const entity of [
      'user',
      'device',
      'team',
      'membership',
      'invitation',
      'receiver',
      'care-instructions',
      'tracker',
      'schedule',
      'entry',
      'journal-note',
      'coverage-schedule',
      'assignment',
    ]) {
      t.hasResourceProperties('AWS::DynamoDB::Table', { TableName: `caregiver-dev-v1-${entity}` });
    }
    t.hasResourceProperties('AWS::DynamoDB::Table', {
      TableName: 'caregiver-dev-v1-invitation',
      TimeToLiveSpecification: { AttributeName: 'expires_at', Enabled: true },
    });
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
    t.hasResourceProperties('AWS::Cognito::UserPoolClient', {
      PreventUserExistenceErrors: 'ENABLED',
    });
  });

  test('v1_api is on in dev and off in prod, and the schema requires it', () => {
    for (const [stage, enabled] of [
      ['dev', true],
      ['prod', false],
    ] as const) {
      const app = new cdk.App();
      const stack = new SharedStack(
        app,
        `Caregiver${stage === 'dev' ? 'Dev' : 'Prod'}-SharedFlags`,
        {
          env: { account: '123456789012', region: 'us-east-2' },
          stage,
        },
      );
      const t = Template.fromStack(stack);
      const versions = t.findResources('AWS::AppConfig::HostedConfigurationVersion');
      const content = JSON.parse(Object.values(versions)[0].Properties.Content);
      expect(content.v1_api).toEqual({ enabled });

      const profiles = t.findResources('AWS::AppConfig::ConfigurationProfile');
      const schema = JSON.parse(Object.values(profiles)[0].Properties.Validators[0].Content);
      expect(schema.required).toContain('v1_api');
      expect(Object.keys(content).sort()).toEqual(Object.keys(schema.properties).sort());
    }
  });
});
