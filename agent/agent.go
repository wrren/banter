package agent

import "github.com/wrren/banter/llm"

type AgentID string

type Agent struct {
	ID          AgentID          `json:"id"`
	Description string           `json:"description"`
	Prompt      llm.SystemPrompt `json:"prompt"`
}
