package llm

type Session struct {
	ProviderID string       `json:"provider_id"`
	ModelID    ModelID      `json:"model_id"`
	Prompt     SystemPrompt `json:"prompt"`
	Messages   []Message    `json:"messages"`
	Tools      []Tool       `json:"tools"`
}
