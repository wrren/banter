package llm

type Session struct {
	ModelID  ModelID      `json:"model_id"`
	Prompt   SystemPrompt `json:"prompt"`
	Messages []Message    `json:"messages"`
	Tools    []Tool       `json:"tools"`
}
