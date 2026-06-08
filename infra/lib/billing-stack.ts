import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as cw from 'aws-cdk-lib/aws-cloudwatch';
import * as budgets from 'aws-cdk-lib/aws-budgets';

export interface BillingStackProps extends cdk.StackProps {
  notificationEmail: string;
}

export class BillingStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: BillingStackProps) {
    super(scope, id, props);

    // CloudWatch billing alarm requires us-east-1 (where AWS publishes billing metrics).
    const cwBillingMetric = new cw.Metric({
      namespace: 'AWS/Billing',
      metricName: 'EstimatedCharges',
      dimensionsMap: { Currency: 'USD' },
      period: cdk.Duration.hours(6),
      statistic: 'Maximum',
    });

    new cw.Alarm(this, 'CloudWatchSpendAlarm', {
      alarmName: 'caregiver-cloudwatch-billing-tripwire',
      metric: cwBillingMetric,
      threshold: 5,
      evaluationPeriods: 1,
      comparisonOperator: cw.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cw.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'Alerts when total CloudWatch-eligible monthly charges exceed $5.',
    });

    new budgets.CfnBudget(this, 'OverallMonthlyBudget', {
      budget: {
        budgetName: 'caregiver-monthly-overall',
        budgetType: 'COST',
        timeUnit: 'MONTHLY',
        budgetLimit: { amount: 20, unit: 'USD' },
      },
      notificationsWithSubscribers: [
        {
          notification: {
            comparisonOperator: 'GREATER_THAN',
            notificationType: 'ACTUAL',
            threshold: 80,
            thresholdType: 'PERCENTAGE',
          },
          subscribers: [{ subscriptionType: 'EMAIL', address: props.notificationEmail }],
        },
      ],
    });
  }
}
