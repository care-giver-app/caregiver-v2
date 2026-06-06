#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { SharedStack } from '../lib/shared-stack';

const app = new cdk.App();

const account = process.env.CDK_DEFAULT_ACCOUNT;
const region = process.env.CDK_DEFAULT_REGION ?? 'us-east-2';
const env = { account, region };

const stage = (app.node.tryGetContext('stage') as string | undefined) ?? 'dev';
if (stage !== 'dev' && stage !== 'prod') {
  throw new Error(`Invalid stage: ${stage}. Must be 'dev' or 'prod'.`);
}

const prefix = stage === 'prod' ? 'CaregiverProd' : 'CaregiverDev';

new SharedStack(app, `${prefix}-Shared`, { env, stage });
