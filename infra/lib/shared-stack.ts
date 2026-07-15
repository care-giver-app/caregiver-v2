import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as appconfig from 'aws-cdk-lib/aws-appconfig';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { defaultFlagContent } from './appconfig-content';

export type Stage = 'dev' | 'prod';

export interface SharedStackProps extends cdk.StackProps {
  stage: Stage;
}

export class SharedStack extends cdk.Stack {
  public readonly alarmTopic: sns.Topic;
  public readonly appConfigApplicationId: string;
  public readonly appConfigEnvironmentId: string;
  public readonly appConfigProfileId: string;
  public readonly tables: {
    users: dynamodb.Table;
    careGroups: dynamodb.Table;
    memberships: dynamodb.Table;
    invitations: dynamodb.Table;
    receivers: dynamodb.Table;
    trackers: dynamodb.Table;
    events: dynamodb.Table;
    scheduledItems: dynamodb.Table;
  };
  public readonly userPool: cognito.UserPool;
  public readonly userPoolClient: cognito.UserPoolClient;

  constructor(scope: Construct, id: string, props: SharedStackProps) {
    super(scope, id, props);

    const stageLabel = props.stage === 'prod' ? 'Prod' : 'Dev';

    this.alarmTopic = new sns.Topic(this, 'AlarmTopic', {
      topicName: `caregiver-${props.stage}-alarms`,
      displayName: `Caregiver ${stageLabel} Alarms`,
    });

    const appConfigApp = new appconfig.CfnApplication(this, 'FlagsApp', {
      name: `caregiver-${props.stage}`,
    });

    const schema = fs.readFileSync(path.join(__dirname, 'appconfig-schema.json'), 'utf-8');

    const profile = new appconfig.CfnConfigurationProfile(this, 'FlagsProfile', {
      applicationId: appConfigApp.ref,
      name: 'flags',
      locationUri: 'hosted',
      type: 'AWS.Freeform',
      validators: [
        {
          type: 'JSON_SCHEMA',
          content: JSON.stringify(JSON.parse(schema)),
        },
      ],
    });

    const env = new appconfig.CfnEnvironment(this, 'FlagsEnv', {
      applicationId: appConfigApp.ref,
      name: props.stage,
    });

    const hostedVersion = new appconfig.CfnHostedConfigurationVersion(this, 'FlagsVersion', {
      applicationId: appConfigApp.ref,
      configurationProfileId: profile.ref,
      contentType: 'application/json',
      content: JSON.stringify(defaultFlagContent),
    });

    const strategy = new appconfig.CfnDeploymentStrategy(this, 'FlagsStrategy', {
      name: `caregiver-${props.stage}-all-at-once`,
      deploymentDurationInMinutes: 0,
      growthFactor: 100,
      finalBakeTimeInMinutes: 0,
      replicateTo: 'NONE',
    });

    new appconfig.CfnDeployment(this, 'FlagsDeploy', {
      applicationId: appConfigApp.ref,
      configurationProfileId: profile.ref,
      configurationVersion: hostedVersion.ref,
      environmentId: env.ref,
      deploymentStrategyId: strategy.ref,
    });

    this.appConfigApplicationId = appConfigApp.ref;
    this.appConfigEnvironmentId = env.ref;
    this.appConfigProfileId = profile.ref;

    new cdk.CfnOutput(this, 'AppConfigApplicationId', { value: this.appConfigApplicationId });
    new cdk.CfnOutput(this, 'AppConfigEnvironmentId', { value: this.appConfigEnvironmentId });
    new cdk.CfnOutput(this, 'AppConfigProfileId', { value: this.appConfigProfileId });

    const removalPolicy =
      props.stage === 'prod' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY;
    const tableBase = {
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy,
      pointInTimeRecoverySpecification: {
        pointInTimeRecoveryEnabled: props.stage === 'prod',
      },
    };
    const s = dynamodb.AttributeType.STRING;

    const users = new dynamodb.Table(this, 'UsersTable', {
      ...tableBase,
      tableName: `caregiver-${props.stage}-user`,
      partitionKey: { name: 'user_id', type: s },
    });
    users.addGlobalSecondaryIndex({
      indexName: 'email-index',
      partitionKey: { name: 'email', type: s },
    });

    const careGroups = new dynamodb.Table(this, 'CareGroupsTable', {
      ...tableBase,
      tableName: `caregiver-${props.stage}-care-group`,
      partitionKey: { name: 'care_group_id', type: s },
    });

    const memberships = new dynamodb.Table(this, 'MembershipsTable', {
      ...tableBase,
      tableName: `caregiver-${props.stage}-membership`,
      partitionKey: { name: 'user_id', type: s },
      sortKey: { name: 'care_group_id', type: s },
    });
    memberships.addGlobalSecondaryIndex({
      indexName: 'group-index',
      partitionKey: { name: 'care_group_id', type: s },
      sortKey: { name: 'user_id', type: s },
    });

    const invitations = new dynamodb.Table(this, 'InvitationsTable', {
      ...tableBase,
      tableName: `caregiver-${props.stage}-invitation`,
      partitionKey: { name: 'token', type: s },
      timeToLiveAttribute: 'expires_at',
    });
    invitations.addGlobalSecondaryIndex({
      indexName: 'group-index',
      partitionKey: { name: 'care_group_id', type: s },
    });
    invitations.addGlobalSecondaryIndex({
      indexName: 'email-index',
      partitionKey: { name: 'email', type: s },
    });

    const receivers = new dynamodb.Table(this, 'ReceiversTable', {
      ...tableBase,
      tableName: `caregiver-${props.stage}-receiver`,
      partitionKey: { name: 'receiver_id', type: s },
    });
    receivers.addGlobalSecondaryIndex({
      indexName: 'group-index',
      partitionKey: { name: 'care_group_id', type: s },
      sortKey: { name: 'created_at', type: s },
    });

    const trackers = new dynamodb.Table(this, 'TrackersTable', {
      ...tableBase,
      tableName: `caregiver-${props.stage}-tracker`,
      partitionKey: { name: 'tracker_id', type: s },
    });
    trackers.addGlobalSecondaryIndex({
      indexName: 'receiver-index',
      partitionKey: { name: 'receiver_id', type: s },
      sortKey: { name: 'created_at', type: s },
    });

    const events = new dynamodb.Table(this, 'EventsTable', {
      ...tableBase,
      tableName: `caregiver-${props.stage}-event`,
      partitionKey: { name: 'tracker_id', type: s },
      sortKey: { name: 'event_id', type: s },
    });
    events.addGlobalSecondaryIndex({
      indexName: 'time-index',
      partitionKey: { name: 'tracker_id', type: s },
      sortKey: { name: 'occurred_at', type: s },
    });

    const scheduledItems = new dynamodb.Table(this, 'ScheduledItemsTable', {
      ...tableBase,
      tableName: `caregiver-${props.stage}-scheduled-item`,
      partitionKey: { name: 'scheduled_item_id', type: s },
    });
    scheduledItems.addGlobalSecondaryIndex({
      indexName: 'tracker-index',
      partitionKey: { name: 'tracker_id', type: s },
      sortKey: { name: 'scheduled_for', type: s },
    });
    scheduledItems.addGlobalSecondaryIndex({
      indexName: 'receiver-index',
      partitionKey: { name: 'receiver_id', type: s },
      sortKey: { name: 'scheduled_for', type: s },
    });

    this.tables = {
      users,
      careGroups,
      memberships,
      invitations,
      receivers,
      trackers,
      events,
      scheduledItems,
    };

    this.userPool = new cognito.UserPool(this, 'UserPool', {
      userPoolName: `caregiver-${props.stage}`,
      selfSignUpEnabled: true,
      signInAliases: { email: true },
      autoVerify: { email: true },
      standardAttributes: {
        email: { required: true, mutable: true },
        fullname: { required: false, mutable: true },
      },
      passwordPolicy: { minLength: 8, requireLowercase: true, requireDigits: true },
      removalPolicy: props.stage === 'prod' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
    });

    // Public client for the native iOS app (no secret). userSrp is what the app
    // uses; adminUserPassword lets server-side test sign-in mint a token.
    this.userPoolClient = this.userPool.addClient('AppClient', {
      userPoolClientName: `caregiver-${props.stage}-app`,
      authFlows: { userSrp: true, adminUserPassword: true },
      generateSecret: false,
    });

    new cdk.CfnOutput(this, 'UserPoolId', { value: this.userPool.userPoolId });
    new cdk.CfnOutput(this, 'UserPoolClientId', { value: this.userPoolClient.userPoolClientId });

    cdk.Tags.of(this).add('Project', 'Caregiver');
    cdk.Tags.of(this).add('Stage', props.stage);
  }
}
