package agent

import "github.com/wrren/banter/llm"

type Session struct {
	llm.Session
	Agent AgentID `json:"agent_id"`
}
