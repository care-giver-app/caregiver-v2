.PHONY: codegen test

OPENAPI := ../openapi/openapi.yaml

codegen:
	mkdir -p caregiverapi
	go tool oapi-codegen -config oapi-config.yaml $(OPENAPI)

test:
	go test ./...
