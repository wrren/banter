package agent

import "github.com/wrren/banter/llm"

type Session struct {
	Agent    AgentID       `json:"agent_id"`
	Model    llm.ModelID   `json:"model_id"`
	Messages []llm.Message `json:"messages"`
}
