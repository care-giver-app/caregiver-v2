#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { SharedStack } from '../lib/shared-stack';
import { ApiStack } from '../lib/api-stack';
import { ObservabilityStack } from '../lib/observability-stack';
import { BillingStack } from '../lib/billing-stack';

const app = new cdk.App();

const account = process.env.CDK_DEFAULT_ACCOUNT;
const region = process.env.CDK_DEFAULT_REGION ?? 'us-east-2';
const env = { account, region };

const stage = (app.node.tryGetContext('stage') as string | undefined) ?? 'dev';
if (stage !== 'dev' && stage !== 'prod') {
  throw new Error(`Invalid stage: ${stage}. Must be 'dev' or 'prod'.`);
}

const prefix = stage === 'prod' ? 'CaregiverProd' : 'CaregiverDev';
const version = process.env.APP_VERSION ?? '0.0.0-dev';

const shared = new SharedStack(app, `${prefix}-Shared`, { env, stage });
const api = new ApiStack(app, `${prefix}-Api`, {
  env,
  stage,
  version,
  appConfigApplicationId: shared.appConfigApplicationId,
  appConfigEnvironmentId: shared.appConfigEnvironmentId,
  appConfigProfileId: shared.appConfigProfileId,
});
new ObservabilityStack(app, `${prefix}-Observability`, {
  env,
  stage,
  apiFunction: api.apiFunction,
  alarmTopic: shared.alarmTopic,
});

if (stage === 'prod') {
  const notificationEmail = process.env.CAREGIVER_ALERT_EMAIL;
  if (!notificationEmail) {
    throw new Error(
      'CAREGIVER_ALERT_EMAIL must be set (non-empty) for prod deploys. ' +
        'Configure via: gh variable set CAREGIVER_ALERT_EMAIL --body "<email>"',
    );
  }
  // BillingStack MUST be in us-east-1: AWS only publishes billing metrics there.
  new BillingStack(app, `${prefix}-Billing`, {
    env: { account: env.account, region: 'us-east-1' },
    notificationEmail,
  });
}

// v1/v2 coexistence guardrail: see ADR-0011.
// All stacks in the CDK app must use the Caregiver{Dev|Prod}- prefix so this
// app can never deploy on top of a v1 (care-giver-*) stack by accident.
const STACK_NAME_PATTERN = /^Caregiver(Dev|Prod)-/;
for (const child of app.node.children) {
  if (cdk.Stack.isStack(child)) {
    if (!STACK_NAME_PATTERN.test(child.stackName)) {
      throw new Error(
        `Stack "${child.stackName}" does not match required pattern ${STACK_NAME_PATTERN}. ` +
          `See docs/adr/0011-v1-v2-coexistence-in-shared-aws-account.md for context.`,
      );
    }
  }
}
