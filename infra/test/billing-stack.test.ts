import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { BillingStack } from '../lib/billing-stack';

describe('BillingStack', () => {
  test('creates a CloudWatch billing alarm and an AWS Budget', () => {
    const app = new cdk.App();
    const stack = new BillingStack(app, 'TestBilling', {
      env: { account: '123456789012', region: 'us-east-1' },
      notificationEmail: 'test@example.com',
    });
    const template = Template.fromStack(stack);
    template.resourceCountIs('AWS::CloudWatch::Alarm', 1);
    template.resourceCountIs('AWS::Budgets::Budget', 1);
  });
});
