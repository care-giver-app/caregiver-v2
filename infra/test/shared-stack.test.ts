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
});
