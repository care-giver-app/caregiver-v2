// Package config centralizes environment-variable parsing so handlers don't
// scatter os.Getenv calls.
package config

import (
	"fmt"
	"os"
)

type Config struct {
	Service string
	Stage   string
	Version string
}

// FromEnv reads required configuration from environment variables.
// SERVICE, STAGE, and APP_VERSION are required.
func FromEnv() (Config, error) {
	c := Config{
		Service: os.Getenv("SERVICE"),
		Stage:   os.Getenv("STAGE"),
		Version: os.Getenv("APP_VERSION"),
	}
	if c.Service == "" || c.Stage == "" || c.Version == "" {
		return c, fmt.Errorf("missing required env: SERVICE=%q STAGE=%q APP_VERSION=%q",
			c.Service, c.Stage, c.Version)
	}
	return c, nil
}
