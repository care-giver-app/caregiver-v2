import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigw from 'aws-cdk-lib/aws-apigatewayv2';
import * as integ from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import { HttpUserPoolAuthorizer } from 'aws-cdk-lib/aws-apigatewayv2-authorizers';
import * as path from 'node:path';
import { execSync } from 'node:child_process';
import type { Stage } from './shared-stack';

export interface ApiStackProps extends cdk.StackProps {
  stage: Stage;
  version: string;
  appConfigApplicationId: string;
  appConfigEnvironmentId: string;
  appConfigProfileId: string;
  userPool: cognito.IUserPool;
  userPoolClient: cognito.IUserPoolClient;
  tables: {
    users: dynamodb.ITable;
    careGroups: dynamodb.ITable;
    memberships: dynamodb.ITable;
    invitations: dynamodb.ITable;
    receivers: dynamodb.ITable;
    trackers: dynamodb.ITable;
    events: dynamodb.ITable;
  };
}

export class ApiStack extends cdk.Stack {
  public readonly apiFunction: lambda.Function;

  constructor(scope: Construct, id: string, props: ApiStackProps) {
    super(scope, id, props);

    const resourceName = `caregiver-${props.stage}-api`;

    const apiRoot = path.resolve(__dirname, '..', '..', 'api');
    const bootstrapDir = path.resolve(apiRoot, 'cmd', 'lambda');

    // Build the Go Lambda binary at synth time.
    execSync(
      'GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -tags lambda.norpc -o bootstrap ./...',
      { cwd: bootstrapDir, stdio: 'inherit' },
    );

    const logGroup = new logs.LogGroup(this, 'ApiFunctionLogs', {
      logGroupName: `/aws/lambda/${resourceName}`,
      retention:
        props.stage === 'prod' ? logs.RetentionDays.ONE_MONTH : logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    this.apiFunction = new lambda.Function(this, 'ApiFunction', {
      functionName: resourceName,
      runtime: lambda.Runtime.PROVIDED_AL2023,
      architecture: lambda.Architecture.ARM_64,
      handler: 'bootstrap',
      code: lambda.Code.fromAsset(bootstrapDir, {
        exclude: ['*.go', '*.mod', '*.sum'],
      }),
      memorySize: 256,
      timeout: cdk.Duration.seconds(10),
      tracing: lambda.Tracing.ACTIVE,
      environment: {
        SERVICE: 'api',
        STAGE: props.stage,
        APP_VERSION: props.version,
      },
      logGroup,
    });

    // ARM64 AppConfig extension layer ARN — region-specific.
    // us-east-2 published account: 728743619870.
    // Layer version below was current at plan-write time; VERIFY against the AWS docs
    // before deploying: https://docs.aws.amazon.com/appconfig/latest/userguide/appconfig-integration-lambda-extensions-versions.html
    const appConfigExtensionLayerArn =
      'arn:aws:lambda:us-east-2:728743619870:layer:AWS-AppConfig-Extension-Arm64:67';

    this.apiFunction.addLayers(
      lambda.LayerVersion.fromLayerVersionArn(
        this,
        'AppConfigExtension',
        appConfigExtensionLayerArn,
      ),
    );

    this.apiFunction.addEnvironment('APPCONFIG_APPLICATION_ID', props.appConfigApplicationId);
    this.apiFunction.addEnvironment('APPCONFIG_ENVIRONMENT_ID', props.appConfigEnvironmentId);
    this.apiFunction.addEnvironment('APPCONFIG_PROFILE_ID', props.appConfigProfileId);

    for (const table of Object.values(props.tables)) {
      table.grantReadWriteData(this.apiFunction);
    }
    this.apiFunction.addEnvironment('USERS_TABLE', props.tables.users.tableName);
    this.apiFunction.addEnvironment('CARE_GROUPS_TABLE', props.tables.careGroups.tableName);
    this.apiFunction.addEnvironment('MEMBERSHIPS_TABLE', props.tables.memberships.tableName);
    this.apiFunction.addEnvironment('INVITATIONS_TABLE', props.tables.invitations.tableName);
    this.apiFunction.addEnvironment('RECEIVERS_TABLE', props.tables.receivers.tableName);
    this.apiFunction.addEnvironment('TRACKERS_TABLE', props.tables.trackers.tableName);
    this.apiFunction.addEnvironment('EVENTS_TABLE', props.tables.events.tableName);

    // AppConfig actions: `StartConfigurationSession` is a control-plane call that
    // doesn't accept a resource ARN, and `GetLatestConfiguration` operates on
    // session tokens — neither supports resource-level scoping. See AWS IAM docs
    // for the appconfig service for the full action/resource matrix.
    this.apiFunction.addToRolePolicy(
      new iam.PolicyStatement({
        actions: ['appconfig:GetLatestConfiguration', 'appconfig:StartConfigurationSession'],
        resources: ['*'],
      }),
    );

    const httpApi = new apigw.HttpApi(this, 'HttpApi', {
      apiName: resourceName,
    });

    httpApi.addRoutes({
      path: '/health',
      methods: [apigw.HttpMethod.GET],
      integration: new integ.HttpLambdaIntegration('HealthIntegration', this.apiFunction),
    });

    httpApi.addRoutes({
      path: '/flags',
      methods: [apigw.HttpMethod.GET],
      integration: new integ.HttpLambdaIntegration('FlagsIntegration', this.apiFunction),
    });

    const authorizer = new HttpUserPoolAuthorizer('JwtAuthorizer', props.userPool, {
      userPoolClients: [props.userPoolClient],
    });
    const lambdaIntegration = new integ.HttpLambdaIntegration('ApiIntegration', this.apiFunction);

    const authedRoutes: Array<{ path: string; methods: apigw.HttpMethod[] }> = [
      { path: '/me', methods: [apigw.HttpMethod.GET] },
      { path: '/care-groups', methods: [apigw.HttpMethod.POST] },
      { path: '/care-groups/{careGroupId}/invitations', methods: [apigw.HttpMethod.POST] },
      {
        path: '/care-groups/{careGroupId}/invitations/{token}',
        methods: [apigw.HttpMethod.DELETE],
      },
      { path: '/invitations/mine', methods: [apigw.HttpMethod.GET] },
      { path: '/invitations/{token}/accept', methods: [apigw.HttpMethod.POST] },
      { path: '/receivers', methods: [apigw.HttpMethod.GET] },
      { path: '/care-groups/{careGroupId}/receivers', methods: [apigw.HttpMethod.POST] },
      { path: '/receivers/{receiverId}', methods: [apigw.HttpMethod.GET] },
      { path: '/receivers/{receiverId}', methods: [apigw.HttpMethod.PATCH] },
      { path: '/receivers/{receiverId}', methods: [apigw.HttpMethod.DELETE] },
      { path: '/receivers/{receiverId}/trackers', methods: [apigw.HttpMethod.GET] },
      { path: '/receivers/{receiverId}/trackers', methods: [apigw.HttpMethod.POST] },
      { path: '/trackers/{trackerId}', methods: [apigw.HttpMethod.GET] },
      { path: '/trackers/{trackerId}', methods: [apigw.HttpMethod.PATCH] },
      { path: '/trackers/{trackerId}', methods: [apigw.HttpMethod.DELETE] },
      { path: '/trackers/{trackerId}/events', methods: [apigw.HttpMethod.GET] },
      { path: '/trackers/{trackerId}/events', methods: [apigw.HttpMethod.POST] },
      { path: '/trackers/{trackerId}/events/{eventId}', methods: [apigw.HttpMethod.GET] },
      { path: '/trackers/{trackerId}/events/{eventId}', methods: [apigw.HttpMethod.PATCH] },
      { path: '/trackers/{trackerId}/events/{eventId}', methods: [apigw.HttpMethod.DELETE] },
      { path: '/tracker-templates', methods: [apigw.HttpMethod.GET] },
    ];
    for (const route of authedRoutes) {
      httpApi.addRoutes({
        path: route.path,
        methods: route.methods,
        integration: lambdaIntegration,
        authorizer,
      });
    }

    new cdk.CfnOutput(this, 'HttpApiUrl', { value: httpApi.apiEndpoint });
  }
}
