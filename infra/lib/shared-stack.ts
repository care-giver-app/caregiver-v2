import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as appconfig from 'aws-cdk-lib/aws-appconfig';
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

    cdk.Tags.of(this).add('Project', 'Caregiver');
    cdk.Tags.of(this).add('Stage', props.stage);
  }
}
