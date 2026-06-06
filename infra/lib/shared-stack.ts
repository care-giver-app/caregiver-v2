import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as sns from 'aws-cdk-lib/aws-sns';

export type Stage = 'dev' | 'prod';

export interface SharedStackProps extends cdk.StackProps {
  stage: Stage;
}

export class SharedStack extends cdk.Stack {
  public readonly alarmTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: SharedStackProps) {
    super(scope, id, props);

    const stageLabel = props.stage === 'prod' ? 'Prod' : 'Dev';

    this.alarmTopic = new sns.Topic(this, 'AlarmTopic', {
      topicName: `caregiver-${props.stage}-alarms`,
      displayName: `Caregiver ${stageLabel} Alarms`,
    });

    cdk.Tags.of(this).add('Project', 'Caregiver');
    cdk.Tags.of(this).add('Stage', props.stage);
  }
}
