import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as sns from 'aws-cdk-lib/aws-sns';
import { ObservabilityStack } from '../lib/observability-stack';

describe('ObservabilityStack', () => {
  test('creates one dashboard and required alarms', () => {
    const app = new cdk.App();
    const refStack = new cdk.Stack(app, 'RefStack', {
      env: { account: '123456789012', region: 'us-east-1' },
    });
    const apiFn = new lambda.Function(refStack, 'TestFn', {
      runtime: lambda.Runtime.NODEJS_20_X,
      handler: 'index.handler',
      code: lambda.Code.fromInline('exports.handler = async () => ({});'),
    });
    const generatorFn = new lambda.Function(refStack, 'GeneratorFn', {
      runtime: lambda.Runtime.NODEJS_20_X,
      handler: 'index.handler',
      code: lambda.Code.fromInline('exports.handler = async () => ({});'),
    });
    const alarmTopic = new sns.Topic(refStack, 'AlarmTopic');

    const stack = new ObservabilityStack(app, 'TestObservability', {
      env: { account: '123456789012', region: 'us-east-1' },
      stage: 'dev',
      apiFunction: apiFn,
      generatorFunction: generatorFn,
      alarmTopic,
    });
    const template = Template.fromStack(stack);
    template.resourceCountIs('AWS::CloudWatch::Dashboard', 1);
    template.resourceCountIs('AWS::CloudWatch::Alarm', 5);
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      AlarmName: 'caregiver-dev-generator-errors',
      MetricName: 'Errors',
      Threshold: 1,
    });
  });
});
