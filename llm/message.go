package llm

import "encoding/json"

type MessageRole string

const (
	MessageRoleDeveloper MessageRole = "developer"
	MessageRoleUser      MessageRole = "user"
	MessageRoleAssistant MessageRole = "assistant"
	MessageRoleTool      MessageRole = "tool"
)

type Message interface {
	GetRole() MessageRole
}

type MessageList []Message

func (ml MessageList) MarshalJSON() ([]byte, error) {
	raw := make([]json.RawMessage, 0, len(ml))
	for _, msg := range ml {
		b, err := json.Marshal(msg)
		if err != nil {
			return nil, err
		}
		raw = append(raw, b)
	}
	return json.Marshal(raw)
}

func (ml MessageList) UnmarshalJSON(data []byte) error {
	var raw []json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	for _, r := range raw {
		var envelope struct {
			Role MessageRole `json:"role"`
		}
		if err := json.Unmarshal(r, &envelope); err != nil {
			return err
		}
		var msg Message
		switch envelope.Role {
		case MessageRoleUser:
			var m UserMessage
			if err := json.Unmarshal(r, &m); err != nil {
				return err
			}
			msg = m
		case MessageRoleDeveloper:
			var m DeveloperMessage
			if err := json.Unmarshal(r, &m); err != nil {
				return err
			}
			msg = m
		case MessageRoleAssistant:
			var m AssistantMessage
			if err := json.Unmarshal(r, &m); err != nil {
				return err
			}
			msg = m
		case MessageRoleTool:
			var m ToolMessage
			if err := json.Unmarshal(r, &m); err != nil {
				return err
			}
			msg = m
		default:
			var m UserMessage
			if err := json.Unmarshal(r, &m); err != nil {
				return err
			}
			msg = m
		}
		ml = append(ml, msg)
	}
	return nil
}

type UserContent struct {
	Parts []UserContentPart `json:"parts"`
}

type UserContentPart interface {
	isUserContentPart()
}

type TextPart struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

func (t TextPart) isUserContentPart() {}

type UserMessage struct {
	Role    MessageRole `json:"role"`
	Content UserContent `json:"content"`
}

func NewUserMessage(content string) UserMessage {
	return UserMessage{
		Role: MessageRoleUser,
		Content: UserContent{
			Parts: []UserContentPart{
				TextPart{
					Type: "text",
					Text: content,
				},
			},
		},
	}
}

func (u UserMessage) GetRole() MessageRole {
	return MessageRoleUser
}

type DeveloperMessage struct {
	Role    MessageRole `json:"role"`
	Content string      `json:"content"`
}

func NewDeveloperMessage(content string) DeveloperMessage {
	return DeveloperMessage{
		Role:    MessageRoleDeveloper,
		Content: content,
	}
}

func (d DeveloperMessage) GetRole() MessageRole {
	return MessageRoleDeveloper
}

type AssistantMessage struct {
	Role      MessageRole `json:"role"`
	Content   *string     `json:"content"`
	ToolCalls []ToolCall  `json:"tool_calls"`
}

func NewAssistantMessage(content string) AssistantMessage {
	return AssistantMessage{
		Role:    MessageRoleAssistant,
		Content: &content,
	}
}

func NewAssistantMessageWithToolCalls(toolCalls []ToolCall) AssistantMessage {
	return AssistantMessage{
		Role:      MessageRoleAssistant,
		Content:   nil,
		ToolCalls: toolCalls,
	}
}

func (a AssistantMessage) GetRole() MessageRole {
	return MessageRoleAssistant
}

type ToolMessage struct {
	Role       MessageRole `json:"role"`
	Content    string      `json:"content"`
	ToolCallID string      `json:"tool_call_id"`
}

func NewToolMessage(result ToolResult) ToolMessage {
	content, _ := json.Marshal(result)
	return ToolMessage{
		Role:       MessageRoleTool,
		Content:    string(content),
		ToolCallID: result.ToolCallID,
	}
}

func (t ToolMessage) GetRole() MessageRole {
	return MessageRoleTool
}
