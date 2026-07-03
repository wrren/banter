package tools

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/microcosm-cc/bluemonday"
)

const maxContentLength = 8192

type WebFetch struct {
	client *http.Client
}

func NewWebFetch() *WebFetch {
	return &WebFetch{
		client: &http.Client{Timeout: 30 * time.Second},
	}
}

func (w *WebFetch) ID() string {
	return "web_fetch"
}

func (w *WebFetch) Description() string {
	return "Fetch the contents of a URL and return the text"
}

func (w *WebFetch) ArgsSchema() ArgsSchema {
	return ArgsSchema{
		Type:                 "object",
		Required:             []string{"url"},
		AdditionalProperties: false,
		Properties: map[string]any{
			"url": map[string]string{
				"type":        "string",
				"description": "The URL to fetch",
			},
		},
	}
}

func (w *WebFetch) Config() map[string]any {
	return map[string]any{}
}

func (w *WebFetch) Invoke(ctx context.Context, args map[string]any) (any, error) {
	urlRaw, ok := args["url"].(string)
	if !ok {
		return nil, fmt.Errorf("url must be a string")
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, urlRaw, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("User-Agent", "banter/1.0")

	resp, err := w.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("fetch returned %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response body: %w", err)
	}

	content := stripToPlainText(string(body))
	if len(content) > maxContentLength {
		content = content[:maxContentLength] + "... [truncated]"
	}

	return map[string]any{
		"succeeded": true,
		"content":   content,
	}, nil
}

func stripToPlainText(html string) string {
	p := bluemonday.UGCPolicy()
	text := p.Sanitize(html)
	text = strings.ReplaceAll(text, "\u00a0", " ")
	text = strings.Join(strings.Fields(text), " ")
	return strings.TrimSpace(text)
}
