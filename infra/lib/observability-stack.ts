import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as cw from 'aws-cdk-lib/aws-cloudwatch';
import * as cwa from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as sns from 'aws-cdk-lib/aws-sns';
import type { Stage } from './shared-stack';

export interface ObservabilityStackProps extends cdk.StackProps {
  stage: Stage;
  apiFunction: lambda.Function;
  alarmTopic: sns.Topic;
}

export class ObservabilityStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: ObservabilityStackProps) {
    super(scope, id, props);

    const errors = props.apiFunction.metricErrors({ period: cdk.Duration.minutes(5) });
    const throttles = props.apiFunction.metricThrottles({ period: cdk.Duration.minutes(5) });
    const duration = props.apiFunction.metricDuration({
      period: cdk.Duration.minutes(5),
      statistic: 'p95',
    });
    const invocations = props.apiFunction.metricInvocations({ period: cdk.Duration.minutes(5) });

    const action = new cwa.SnsAction(props.alarmTopic);

    const errorAlarm = new cw.Alarm(this, 'ApiErrorAlarm', {
      alarmName: `caregiver-${props.stage}-api-errors`,
      metric: errors,
      threshold: 5,
      evaluationPeriods: 1,
      comparisonOperator: cw.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cw.TreatMissingData.NOT_BREACHING,
    });
    errorAlarm.addAlarmAction(action);

    const latencyAlarm = new cw.Alarm(this, 'ApiLatencyAlarm', {
      alarmName: `caregiver-${props.stage}-api-p95-latency`,
      metric: duration,
      threshold: 2000,
      evaluationPeriods: 2,
      comparisonOperator: cw.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cw.TreatMissingData.NOT_BREACHING,
    });
    latencyAlarm.addAlarmAction(action);

    const throttleAlarm = new cw.Alarm(this, 'ApiThrottleAlarm', {
      alarmName: `caregiver-${props.stage}-api-throttles`,
      metric: throttles,
      threshold: 1,
      evaluationPeriods: 1,
      comparisonOperator: cw.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cw.TreatMissingData.NOT_BREACHING,
    });
    throttleAlarm.addAlarmAction(action);

    const noInvocationsAlarm = new cw.Alarm(this, 'ApiNoInvocationsAlarm', {
      alarmName: `caregiver-${props.stage}-api-no-invocations`,
      metric: invocations,
      threshold: 0,
      evaluationPeriods: 3,
      comparisonOperator: cw.ComparisonOperator.LESS_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cw.TreatMissingData.BREACHING,
    });
    // noInvocationsAlarm is noisy on dev (low traffic), so the alarm resource is
    // always created (visible on the dashboard) but only notifies SNS in prod.
    if (props.stage === 'prod') {
      noInvocationsAlarm.addAlarmAction(action);
    }

    new cw.Dashboard(this, 'Dashboard', {
      dashboardName: `Caregiver-${props.stage === 'prod' ? 'Prod' : 'Dev'}-Overview`,
      widgets: [
        [
          new cw.GraphWidget({
            title: 'API errors / 5m',
            left: [errors],
          }),
          new cw.GraphWidget({
            title: 'API p95 duration (ms) / 5m',
            left: [duration],
          }),
        ],
        [
          new cw.GraphWidget({
            title: 'API invocations / 5m',
            left: [invocations],
          }),
          new cw.GraphWidget({
            title: 'API throttles / 5m',
            left: [throttles],
          }),
        ],
      ],
    });
  }
}
