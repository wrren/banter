package llm

import (
	"github.com/wrren/banter/tools"
)

type Session struct {
	ModelID  ModelID             `json:"model_id"`
	Prompt   SystemPrompt        `json:"prompt"`
	Messages MessageList         `json:"messages"`
	Tools    tools.ToolsRegistry `json:"tools"`
}

func (s *Session) AppendUserTextMessage(text string) {
	s.Messages = append(s.Messages, NewUserMessage(text))
}
