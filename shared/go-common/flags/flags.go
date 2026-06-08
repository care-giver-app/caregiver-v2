// Package flags fetches the current feature-flag configuration from the
// AppConfig Lambda extension, which exposes a local HTTP endpoint on
// http://localhost:2772/applications/{appId}/environments/{envId}/configurations/{profileId}.
//
// In Lambda, the extension caches values in-process (default 45s TTL), so
// every call here is effectively free after the first hit.
package flags

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// Client fetches feature flags from the AppConfig Lambda extension.
type Client struct {
	url        string
	httpClient *http.Client
}

// NewClient builds a Client targeting the given extension URL.
func NewClient(url string) *Client {
	return &Client{
		url:        url,
		httpClient: &http.Client{Timeout: 2 * time.Second},
	}
}

// NewClientFromEnv builds the extension URL from APPCONFIG_* environment variables.
func NewClientFromEnv(appID, envID, profileID string) *Client {
	url := fmt.Sprintf(
		"http://localhost:2772/applications/%s/environments/%s/configurations/%s",
		appID, envID, profileID,
	)
	return NewClient(url)
}

// Get fetches and JSON-decodes the current flag configuration.
func (c *Client) Get(ctx context.Context) (map[string]any, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.url, nil)
	if err != nil {
		return nil, err
	}
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("appconfig extension returned %d: %s", resp.StatusCode, body)
	}
	var out map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, err
	}
	return out, nil
}
