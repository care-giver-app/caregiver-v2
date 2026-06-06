module github.com/care-giver-app/caregiver-v2/api

go 1.23.7

replace github.com/care-giver-app/caregiver-v2/shared/go-common => ../shared/go-common

require (
	github.com/aws/aws-lambda-go v1.54.0
	github.com/awslabs/aws-lambda-go-api-proxy v0.16.2
	github.com/care-giver-app/caregiver-v2/shared/go-common v0.0.0-00010101000000-000000000000
)
