import * as cdk from 'aws-cdk-lib';
import { Match, Template } from 'aws-cdk-lib/assertions';
import { ApiStack } from '../lib/api-stack';
import { SharedStack } from '../lib/shared-stack';

describe('ApiStack', () => {
  test('creates a Lambda function and HTTP API', () => {
    const app = new cdk.App();
    const env = { account: '123456789012', region: 'us-east-2' };
    const shared = new SharedStack(app, 'CaregiverDev-Shared', { env, stage: 'dev' });
    const stack = new ApiStack(app, 'CaregiverDev-Api', {
      env,
      stage: 'dev',
      version: '0.0.0-test',
      appConfigApplicationId: 'app-test',
      appConfigEnvironmentId: 'env-test',
      appConfigProfileId: 'profile-test',
      userPool: shared.userPool,
      userPoolClient: shared.userPoolClient,
      tables: shared.tables,
      v1Tables: shared.v1Tables,
    });
    const template = Template.fromStack(stack);
    // Every route invokes the `live` alias through one API-wide statement on the alias's own
    // policy, keeping the function's 20 KB resource policy clear.
    template.hasResourceProperties('AWS::Lambda::Alias', { Name: 'live' });
    const invokes = template.findResources('AWS::Lambda::Permission', {
      Properties: { Principal: 'apigateway.amazonaws.com' },
    });
    expect(Object.values(invokes)).toHaveLength(1);
    expect(Object.values(invokes)[0].Properties.FunctionName.Ref).toMatch(/^ApiLive/);
    template.hasResourceProperties('AWS::Lambda::Function', {
      Runtime: 'provided.al2023',
      Architectures: ['arm64'],
      TracingConfig: { Mode: 'Active' },
    });
    template.hasResourceProperties('AWS::Lambda::Function', {
      Layers: Match.arrayWith([Match.stringLikeRegexp('AWS-AppConfig-Extension')]),
      Environment: {
        Variables: Match.objectLike({
          APPCONFIG_APPLICATION_ID: 'app-test',
          APPCONFIG_ENVIRONMENT_ID: 'env-test',
          APPCONFIG_PROFILE_ID: 'profile-test',
          LOG_LEVEL: 'debug',
        }),
      },
    });
    template.hasResourceProperties('AWS::IAM::Policy', {
      PolicyDocument: Match.objectLike({
        Statement: Match.arrayWith([
          Match.objectLike({
            Action: Match.arrayWith([
              'appconfig:GetLatestConfiguration',
              'appconfig:StartConfigurationSession',
            ]),
          }),
        ]),
      }),
    });
    template.resourceCountIs('AWS::ApiGatewayV2::Api', 1);
    template.hasResourceProperties('AWS::ApiGatewayV2::Route', { RouteKey: 'GET /health' });
    template.hasResourceProperties('AWS::ApiGatewayV2::Route', { RouteKey: 'GET /flags' });
  });

  test('wires a v2-specific custom domain with a DNS-validated cert and alias record', () => {
    const app = new cdk.App();
    const env = { account: '123456789012', region: 'us-east-2' };
    const shared = new SharedStack(app, 'CaregiverDev-Shared', { env, stage: 'dev' });
    const stack = new ApiStack(app, 'CaregiverDev-Api', {
      env,
      stage: 'dev',
      version: '0.0.0-test',
      appConfigApplicationId: 'app-test',
      appConfigEnvironmentId: 'env-test',
      appConfigProfileId: 'profile-test',
      userPool: shared.userPool,
      userPoolClient: shared.userPoolClient,
      tables: shared.tables,
      v1Tables: shared.v1Tables,
    });
    const template = Template.fromStack(stack);
    // Dev uses api-v2-dev (NOT v1's api-dev), with a DNS-validated regional cert.
    template.hasResourceProperties('AWS::CertificateManager::Certificate', {
      DomainName: 'api-v2-dev.caretosher.com',
      ValidationMethod: 'DNS',
    });
    template.hasResourceProperties('AWS::ApiGatewayV2::DomainName', {
      DomainName: 'api-v2-dev.caretosher.com',
    });
    template.resourceCountIs('AWS::ApiGatewayV2::ApiMapping', 1);
    template.hasResourceProperties('AWS::Route53::RecordSet', {
      Name: 'api-v2-dev.caretosher.com.',
      Type: 'A',
    });
  });

  test('prod uses api-v2 (the canonical name is reserved for the v1 cutover)', () => {
    const app = new cdk.App();
    const env = { account: '123456789012', region: 'us-east-2' };
    const shared = new SharedStack(app, 'CaregiverProd-Shared', { env, stage: 'prod' });
    const stack = new ApiStack(app, 'CaregiverProd-Api', {
      env,
      stage: 'prod',
      version: '0.0.0-test',
      appConfigApplicationId: 'app-test',
      appConfigEnvironmentId: 'env-test',
      appConfigProfileId: 'profile-test',
      userPool: shared.userPool,
      userPoolClient: shared.userPoolClient,
      tables: shared.tables,
      v1Tables: shared.v1Tables,
    });
    const template = Template.fromStack(stack);
    template.hasResourceProperties('AWS::ApiGatewayV2::DomainName', {
      DomainName: 'api-v2.caretosher.com',
    });
    template.hasResourceProperties('AWS::Lambda::Function', {
      Environment: {
        Variables: Match.objectLike({ LOG_LEVEL: 'info' }),
      },
    });
  });

  test('api stack wires a JWT authorizer and authed routes', () => {
    const app = new cdk.App();
    const env = { account: '123456789012', region: 'us-east-2' };
    const shared = new SharedStack(app, 'CaregiverDev-Shared', { env, stage: 'dev' });
    const apiStack = new ApiStack(app, 'CaregiverDev-Api', {
      env,
      stage: 'dev',
      version: '0.0.0',
      appConfigApplicationId: 'app',
      appConfigEnvironmentId: 'envid',
      appConfigProfileId: 'prof',
      userPool: shared.userPool,
      userPoolClient: shared.userPoolClient,
      tables: shared.tables,
      v1Tables: shared.v1Tables,
    });
    const t = Template.fromStack(apiStack);
    t.resourceCountIs('AWS::ApiGatewayV2::Authorizer', 1);
    t.hasResourceProperties('AWS::ApiGatewayV2::Authorizer', { AuthorizerType: 'JWT' });
    t.resourceCountIs('AWS::ApiGatewayV2::Route', 90);

    for (const routeKey of [
      'GET /me',
      'POST /care-groups',
      'GET /care-groups/{careGroupId}/members',
      'POST /care-groups/{careGroupId}/invitations',
      'DELETE /care-groups/{careGroupId}/invitations/{token}',
      'GET /invitations/mine',
      'POST /invitations/{token}/accept',
      'GET /receivers',
      'POST /trackers/{trackerId}/events',
      'GET /tracker-templates',
      'GET /trackers/{trackerId}/scheduled-items',
      'POST /trackers/{trackerId}/scheduled-items',
      'GET /receivers/{receiverId}/scheduled-items',
      'GET /scheduled-items/{scheduledItemId}',
      'PUT /scheduled-items/{scheduledItemId}',
      'DELETE /scheduled-items/{scheduledItemId}',
      'GET /v1/me',
      'POST /v1/teams',
      'GET /v1/me/invitations',
      'POST /v1/invitations/redeem',
      'GET /v1/teams/{teamId}/receivers',
      'GET /v1/receivers/{receiverId}/trackers',
      'POST /v1/receivers/{receiverId}/trackers',
      'GET /v1/trackers/{trackerId}',
      'PUT /v1/trackers/{trackerId}',
      'POST /v1/trackers/{trackerId}/pause',
      'POST /v1/trackers/{trackerId}/resume',
      'GET /v1/trackers/{trackerId}/entries',
      'GET /v1/trackers/{trackerId}/schedules',
      'POST /v1/trackers/{trackerId}/schedules',
      'PUT /v1/schedules/{scheduleId}',
      'DELETE /v1/schedules/{scheduleId}',
      'GET /v1/tracker-templates',
      'GET /v1/receivers/{receiverId}/attention',
      'GET /v1/receivers/{receiverId}/coming-up',
      'GET /v1/receivers/{receiverId}/timeline',
      'GET /v1/receivers/{receiverId}/waiting',
      'GET /v1/entries/{entryId}',
      'GET /v1/journal-notes/{noteId}',
      'POST /v1/trackers/{trackerId}/entries',
      'POST /v1/entries/{entryId}/log',
      'POST /v1/entries/{entryId}/skip',
      'PUT /v1/entries/{entryId}',
      'DELETE /v1/entries/{entryId}',
      'POST /v1/receivers/{receiverId}/journal-notes',
      'PUT /v1/journal-notes/{noteId}',
      'DELETE /v1/journal-notes/{noteId}',
      'POST /v1/teams/{teamId}/receivers',
      'GET /v1/teams/{teamId}',
      'POST /v1/teams/{teamId}/close',
      'GET /v1/teams/{teamId}/invitations',
      'POST /v1/teams/{teamId}/invitations',
      'PUT /v1/teams/{teamId}/members/{userId}',
      'DELETE /v1/teams/{teamId}/members/{userId}',
      'GET /v1/teams/{teamId}/my-notifications',
      'PUT /v1/teams/{teamId}/my-notifications',
      'GET /v1/receivers/{receiverId}',
      'PUT /v1/receivers/{receiverId}',
      'POST /v1/receivers/{receiverId}/archive',
      'POST /v1/receivers/{receiverId}/restore',
      'PUT /v1/receivers/{receiverId}/care-instructions',
      'PUT /v1/receivers/{receiverId}/emergency-contacts',
      'GET /v1/receivers/{receiverId}/on-duty',
      'GET /v1/receivers/{receiverId}/assignments',
      'POST /v1/receivers/{receiverId}/assignments',
      'PUT /v1/assignments/{assignmentId}',
      'DELETE /v1/assignments/{assignmentId}',
      'GET /v1/receivers/{receiverId}/coverage-schedules',
      'POST /v1/receivers/{receiverId}/coverage-schedules',
      'PUT /v1/coverage-schedules/{coverageScheduleId}',
      'DELETE /v1/coverage-schedules/{coverageScheduleId}',
      'PATCH /v1/me',
      'POST /v1/me/email',
      'POST /v1/me/close',
    ]) {
      t.hasResourceProperties('AWS::ApiGatewayV2::Route', {
        RouteKey: routeKey,
        AuthorizationType: 'JWT',
      });
    }
    // Send feedback takes a token or none, so the Lambda verifies it, not the gateway.
    for (const routeKey of ['GET /health', 'GET /flags', 'POST /v1/feedback']) {
      t.hasResourceProperties('AWS::ApiGatewayV2::Route', {
        RouteKey: routeKey,
        AuthorizationType: 'NONE',
      });
    }
  });

  test('settings: feedback topic, throttled anonymous route, scoped Cognito admin calls', () => {
    const app = new cdk.App();
    const env = { account: '123456789012', region: 'us-east-2' };
    const shared = new SharedStack(app, 'CaregiverDev-Shared', { env, stage: 'dev' });
    const apiStack = new ApiStack(app, 'CaregiverDev-Api', {
      env,
      stage: 'dev',
      version: '0.0.0',
      appConfigApplicationId: 'app',
      appConfigEnvironmentId: 'envid',
      appConfigProfileId: 'prof',
      userPool: shared.userPool,
      userPoolClient: shared.userPoolClient,
      tables: shared.tables,
      v1Tables: shared.v1Tables,
    });
    const t = Template.fromStack(apiStack);
    t.hasResourceProperties('AWS::SNS::Topic', { TopicName: 'caregiver-dev-feedback' });
    t.hasResourceProperties('AWS::SNS::Subscription', {
      Protocol: 'email',
      Endpoint: 'support@caretosher.com',
    });
    t.hasResourceProperties('AWS::Lambda::Function', {
      Environment: {
        Variables: Match.objectLike({
          V1_FEEDBACK_TOPIC_ARN: Match.anyValue(),
          COGNITO_USER_POOL_ID: Match.anyValue(),
          COGNITO_APP_CLIENT_ID: Match.anyValue(),
        }),
      },
    });
    // The function's role has outgrown one inline policy, so CDK spills statements into
    // managed overflow policies: look in both.
    const statements = [
      ...Object.values(t.findResources('AWS::IAM::Policy')),
      ...Object.values(t.findResources('AWS::IAM::ManagedPolicy')),
    ].flatMap(
      (p) => p.Properties.PolicyDocument.Statement as { Action: unknown; Resource: unknown }[],
    );
    const cognitoAdmin = statements.filter((st) => JSON.stringify(st.Action).includes('cognito'));
    expect(cognitoAdmin).toHaveLength(1);
    expect(cognitoAdmin[0].Action).toEqual([
      'cognito-idp:AdminInitiateAuth',
      'cognito-idp:AdminUpdateUserAttributes',
      'cognito-idp:AdminDeleteUser',
    ]);
    expect(JSON.stringify(cognitoAdmin[0].Resource)).toMatch(/UserPool/);
    const publish = statements.filter((st) => JSON.stringify(st.Action).includes('sns:Publish'));
    expect(publish).toHaveLength(1);
    expect(JSON.stringify(publish[0].Resource)).toMatch(/FeedbackTopic/);
    t.hasResourceProperties('AWS::ApiGatewayV2::Stage', {
      StageName: '$default',
      RouteSettings: {
        'POST /v1/feedback': { ThrottlingBurstLimit: 5, ThrottlingRateLimit: 1 },
      },
    });
  });

  test('prod feedback also goes to the support address', () => {
    const app = new cdk.App();
    const env = { account: '123456789012', region: 'us-east-2' };
    const shared = new SharedStack(app, 'CaregiverProd-Shared', { env, stage: 'prod' });
    const apiStack = new ApiStack(app, 'CaregiverProd-Api', {
      env,
      stage: 'prod',
      version: '0.0.0',
      appConfigApplicationId: 'app',
      appConfigEnvironmentId: 'envid',
      appConfigProfileId: 'prof',
      userPool: shared.userPool,
      userPoolClient: shared.userPoolClient,
      tables: shared.tables,
      v1Tables: shared.v1Tables,
    });
    const t = Template.fromStack(apiStack);
    t.hasResourceProperties('AWS::SNS::Topic', { TopicName: 'caregiver-prod-feedback' });
    t.hasResourceProperties('AWS::SNS::Subscription', {
      Protocol: 'email',
      Endpoint: 'support@caretosher.com',
    });
  });

  test('gives the API the getting-in, trackers, home and team v1 tables and no others', () => {
    const app = new cdk.App();
    const env = { account: '123456789012', region: 'us-east-2' };
    const shared = new SharedStack(app, 'CaregiverDev-Shared', { env, stage: 'dev' });
    const apiStack = new ApiStack(app, 'CaregiverDev-Api', {
      env,
      stage: 'dev',
      version: '0.0.0',
      appConfigApplicationId: 'app',
      appConfigEnvironmentId: 'envid',
      appConfigProfileId: 'prof',
      userPool: shared.userPool,
      userPoolClient: shared.userPoolClient,
      tables: shared.tables,
      v1Tables: shared.v1Tables,
    });
    const t = Template.fromStack(apiStack);
    const json = JSON.stringify(t.toJSON());
    for (const name of [
      'V1_USERS_TABLE',
      'V1_TEAMS_TABLE',
      'V1_MEMBERSHIPS_TABLE',
      'V1_INVITATIONS_TABLE',
      'V1_RECEIVERS_TABLE',
      'V1_CARE_INSTRUCTIONS_TABLE',
      'V1_TRACKERS_TABLE',
      'V1_SCHEDULES_TABLE',
      'V1_ENTRIES_TABLE',
      'V1_JOURNAL_NOTES_TABLE',
      'V1_COVERAGE_SCHEDULES_TABLE',
      'V1_ASSIGNMENTS_TABLE',
    ]) {
      expect(json).toContain(name);
    }
    for (const id of [
      'V1UserTable',
      'V1TeamTable',
      'V1MembershipTable',
      'V1InvitationTable',
      'V1ReceiverTable',
      'V1CareInstructionsTable',
      'V1TrackerTable',
      'V1ScheduleTable',
      'V1EntryTable',
      'V1JournalNoteTable',
      'V1CoverageScheduleTable',
      'V1AssignmentTable',
    ]) {
      expect(json).toContain(id);
    }
    for (const id of ['V1DeviceTable']) {
      expect(json).not.toContain(id);
    }
  });

  test('runs the occurrence generator daily at 09:00 UTC with only the tables it needs', () => {
    const app = new cdk.App();
    const env = { account: '123456789012', region: 'us-east-2' };
    const shared = new SharedStack(app, 'CaregiverDev-Shared', { env, stage: 'dev' });
    const apiStack = new ApiStack(app, 'CaregiverDev-Api', {
      env,
      stage: 'dev',
      version: '0.0.0',
      appConfigApplicationId: 'app',
      appConfigEnvironmentId: 'envid',
      appConfigProfileId: 'prof',
      userPool: shared.userPool,
      userPoolClient: shared.userPoolClient,
      tables: shared.tables,
      v1Tables: shared.v1Tables,
    });
    const t = Template.fromStack(apiStack);
    t.hasResourceProperties('AWS::Lambda::Function', {
      FunctionName: 'caregiver-dev-generator',
      Runtime: 'provided.al2023',
      Architectures: ['arm64'],
      Handler: 'bootstrap',
      Environment: {
        Variables: Match.objectLike({
          SERVICE: 'generator',
          STAGE: 'dev',
          V1_RECEIVERS_TABLE: Match.anyValue(),
          V1_TRACKERS_TABLE: Match.anyValue(),
          V1_SCHEDULES_TABLE: Match.anyValue(),
          V1_ENTRIES_TABLE: Match.anyValue(),
          V1_TEAMS_TABLE: Match.anyValue(),
          V1_MEMBERSHIPS_TABLE: Match.anyValue(),
          V1_COVERAGE_SCHEDULES_TABLE: Match.anyValue(),
          V1_ASSIGNMENTS_TABLE: Match.anyValue(),
        }),
      },
    });
    t.hasResourceProperties('AWS::Logs::LogGroup', {
      LogGroupName: '/aws/lambda/caregiver-dev-generator',
      RetentionInDays: 7,
    });
    t.hasResourceProperties('AWS::Events::Rule', {
      ScheduleExpression: 'cron(0 9 * * ? *)',
      State: 'ENABLED',
    });
    t.resourceCountIs('AWS::Events::Rule', 1);
    t.hasOutput('GeneratorFunctionName', {});

    // The generator's policy names only the tables it reads or writes.
    const policies = t.findResources('AWS::IAM::Policy');
    const generatorPolicy = Object.entries(policies).find(([id]) =>
      id.startsWith('GeneratorFunctionServiceRoleDefaultPolicy'),
    );
    expect(generatorPolicy).toBeDefined();
    const doc = JSON.stringify(generatorPolicy![1]);
    for (const id of [
      'V1TeamTable',
      'V1MembershipTable',
      'V1ReceiverTable',
      'V1TrackerTable',
      'V1ScheduleTable',
      'V1EntryTable',
      'V1CoverageScheduleTable',
      'V1AssignmentTable',
    ]) {
      expect(doc).toContain(id);
    }
    for (const id of ['V1UserTable', 'V1InvitationTable', 'V1JournalNoteTable']) {
      expect(doc).not.toContain(id);
    }
  });
});
