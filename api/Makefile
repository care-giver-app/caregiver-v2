.PHONY: features smoke-dev

DEV_REGION := us-east-2
DEV_STACK  := CaregiverDev-Shared
stack_output = $(shell aws cloudformation describe-stacks --region $(DEV_REGION) --stack-name $(DEV_STACK) \
	--query "Stacks[0].Outputs[?OutputKey=='$(1)'].OutputValue" --output text)

# The Gherkin features in features/, in-process against DynamoDB Local (needs
# Docker). Plain `go test ./...` runs these too.
features:
	go test ./features/... -run TestFeatures -count=1 -v

# The same features against the deployed dev API, with throwaway Cognito users
# that are deleted afterwards. Needs valid AWS credentials for the dev account
# (CloudFormation read, Cognito admin, and DynamoDB on the caregiver-dev-v1-* tables).
# Every scenario makes real round trips to dev, so the suite runs past go test's
# default 10m timeout; a timeout kills it before cleanup runs.
smoke-dev:
	FEATURES_TARGET=dev \
	DEV_USER_POOL_ID="$(call stack_output,UserPoolId)" \
	DEV_USER_POOL_CLIENT_ID="$(call stack_output,UserPoolClientId)" \
	go test ./features/... -run TestFeatures -count=1 -v -timeout 30m
