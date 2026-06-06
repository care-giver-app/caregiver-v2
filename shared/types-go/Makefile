.PHONY: codegen test

OPENAPI := ../openapi/openapi.yaml

codegen:
	mkdir -p caregiverapi
	go run github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen -config oapi-config.yaml $(OPENAPI)

test:
	go test ./...
