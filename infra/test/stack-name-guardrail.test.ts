import * as cdk from 'aws-cdk-lib';
import { SharedStack } from '../lib/shared-stack';

// These tests verify the guardrail by simulating what bin/app.ts does:
// build the app, then run the validation loop. We extract the validation
// into a helper here so we can test it without re-running the entrypoint.

function validateStackNames(app: cdk.App): void {
  const STACK_NAME_PATTERN = /^Caregiver(Dev|Prod)-/;
  for (const child of app.node.children) {
    if (cdk.Stack.isStack(child)) {
      if (!STACK_NAME_PATTERN.test(child.stackName)) {
        throw new Error(
          `Stack "${child.stackName}" does not match required pattern ${STACK_NAME_PATTERN}.`,
        );
      }
    }
  }
}

describe('Stack-name guardrail', () => {
  test('passes when stacks use the CaregiverDev- prefix', () => {
    const app = new cdk.App();
    new SharedStack(app, 'CaregiverDev-Shared', {
      env: { account: '123456789012', region: 'us-east-2' },
      stage: 'dev',
    });
    expect(() => validateStackNames(app)).not.toThrow();
  });

  test('passes when stacks use the CaregiverProd- prefix', () => {
    const app = new cdk.App();
    new SharedStack(app, 'CaregiverProd-Shared', {
      env: { account: '123456789012', region: 'us-east-2' },
      stage: 'prod',
    });
    expect(() => validateStackNames(app)).not.toThrow();
  });

  test('throws when a stack name does not match the pattern', () => {
    const app = new cdk.App();
    new SharedStack(app, 'care-giver-api-prod', {
      env: { account: '123456789012', region: 'us-east-2' },
      stage: 'prod',
    });
    expect(() => validateStackNames(app)).toThrow(/does not match required pattern/);
  });

  test('throws on a typo like CaregiverStaging-', () => {
    const app = new cdk.App();
    new SharedStack(app, 'CaregiverStaging-Shared', {
      env: { account: '123456789012', region: 'us-east-2' },
      stage: 'dev',
    });
    expect(() => validateStackNames(app)).toThrow(/does not match required pattern/);
  });
});
