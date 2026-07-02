package tools

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

type BraveSearch struct {
	apiKey string
	client *http.Client
}

func NewBraveSearch(apiKey string) *BraveSearch {
	return &BraveSearch{
		apiKey: apiKey,
		client: &http.Client{},
	}
}

func (b *BraveSearch) ID() string {
	return "brave_search"
}

type braveSearchArgs struct {
	Query string `json:"query"`
}

func (b *BraveSearch) Description() string {
	return "Tool for performing web searches using the Brave search API"
}

func (b *BraveSearch) ArgsSchema() ArgsSchema {
	return ArgsSchema{
		Type:                 "object",
		Required:             []string{"q"},
		AdditionalProperties: false,
		Properties: map[string]any{
			"q": map[string]string{
				"type":        "string",
				"description": "Search Query",
			},
		},
	}
}

func (b *BraveSearch) Config() map[string]any {
	return map[string]any{"api_key": b.apiKey}
}

func (b *BraveSearch) Invoke(ctx context.Context, args map[string]any) (any, error) {
	argsJSON, err := json.Marshal(args)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal args: %w", err)
	}
	var parsed braveSearchArgs
	if err := json.Unmarshal(argsJSON, &parsed); err != nil {
		return nil, fmt.Errorf("failed to parse args: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "https://api.search.brave.com/res/v1/web/search", nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Accept-Encoding", "gzip")
	req.Header.Set("X-Subscription-Token", b.apiKey)
	q := req.URL.Query()
	q.Set("q", parsed.Query)
	req.URL.RawQuery = q.Encode()

	resp, err := b.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("brave search API returned %d: %s", resp.StatusCode, string(body))
	}

	var result struct {
		WebResults struct {
			Results []struct {
				Title   string `json:"title"`
				URL     string `json:"url"`
				Excerpt string `json:"snippet"`
			} `json:"results"`
		} `json:"web_results"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	snippets := make([]map[string]any, 0, len(result.WebResults.Results))
	for _, r := range result.WebResults.Results {
		snippets = append(snippets, map[string]any{
			"title":   r.Title,
			"url":     r.URL,
			"excerpt": r.Excerpt,
		})
	}

	return map[string]any{
		"succeeded": true,
		"results":   snippets,
	}, nil
}
