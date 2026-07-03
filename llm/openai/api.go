package openai

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/wrren/banter/llm"
	"github.com/wrren/banter/tools"
)

type openaiMessage struct {
	Role       string      `json:"role"`
	Content    interface{} `json:"content"`
	Name       string      `json:"name,omitempty"`
	ToolCalls  []toolCall  `json:"tool_calls,omitempty"`
	ToolCallID string      `json:"tool_call_id,omitempty"`
}

type toolCall struct {
	ID       string       `json:"id"`
	Type     string       `json:"type"`
	Function functionCall `json:"function"`
}

type functionCall struct {
	Name      string `json:"name"`
	Arguments string `json:"arguments"`
}

type openaiTool struct {
	Type     string         `json:"type"`
	Function openaiFunction `json:"function"`
}

type openaiFunction struct {
	Name        string           `json:"name"`
	Description string           `json:"description,omitempty"`
	Parameters  tools.ArgsSchema `json:"parameters"`
}

type chatCompletionRequest struct {
	Model      string          `json:"model"`
	Messages   []openaiMessage `json:"messages"`
	Tools      []openaiTool    `json:"tools,omitempty"`
	ToolChoice interface{}     `json:"tool_choice,omitempty"`
}

type chatCompletionResponse struct {
	ID      string    `json:"id"`
	Object  string    `json:"object"`
	Created int64     `json:"created"`
	Model   string    `json:"model"`
	Choices []choice  `json:"choices"`
	Error   *apiError `json:"error,omitempty"`
}

type choice struct {
	Index        int           `json:"index"`
	Message      openaiMessage `json:"message"`
	FinishReason string        `json:"finish_reason"`
	LogProbs     interface{}   `json:"logprobs"`
}

type apiError struct {
	Message string      `json:"message"`
	Type    string      `json:"type"`
	Code    interface{} `json:"code"`
}

func SendCompletion(baseURL, apiKey string, session *llm.Session) ([]llm.Message, error) {
	messages := make([]openaiMessage, 0)

	if session.Prompt.Content != "" {
		messages = append(messages, openaiMessage{
			Role:    "system",
			Content: session.Prompt.Content,
		})
	}

	for _, msg := range session.Messages {
		om := messageToOpenAI(msg)
		messages = append(messages, om)
	}

	var openaiTools []openaiTool
	for n, t := range session.Tools.Tools() {
		openaiTools = append(openaiTools, openaiTool{
			Type: "function",
			Function: openaiFunction{
				Name:       n,
				Parameters: t.ArgsSchema(),
			},
		})
	}

	reqBody := chatCompletionRequest{
		Model:    string(session.ModelID),
		Messages: messages,
		Tools:    openaiTools,
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	url := fmt.Sprintf("%s/v1/chat/completions", baseURL)
	httpReq, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+apiKey)

	client := &http.Client{Timeout: 120 * time.Second}
	resp, err := client.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		var apiErr apiError
		if json.Unmarshal(body, &apiErr) == nil && apiErr.Message != "" {
			return nil, fmt.Errorf("API error (%d): %s", resp.StatusCode, apiErr.Message)
		}
		return nil, fmt.Errorf("API error (%d): %s", resp.StatusCode, string(body))
	}

	var chatResp chatCompletionResponse
	if err := json.Unmarshal(body, &chatResp); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if len(chatResp.Choices) == 0 {
		return nil, fmt.Errorf("no choices in response")
	}

	result := chatResp.Choices[0].Message
	return []llm.Message{openAIMessageToResult(result)}, nil
}

func messageToOpenAI(msg llm.Message) openaiMessage {
	switch m := msg.(type) {
	case llm.UserMessage:
		return openaiMessage{
			Role:    "user",
			Content: contentToOpenAIContent(m.Content),
		}
	case llm.DeveloperMessage:
		return openaiMessage{
			Role:    "system",
			Content: m.Content,
		}
	case llm.AssistantMessage:
		om := openaiMessage{
			Role: "assistant",
		}
		if m.Content != nil {
			om.Content = *m.Content
		}
		if len(m.ToolCalls) > 0 {
			om.ToolCalls = make([]toolCall, 0, len(m.ToolCalls))
			for _, tc := range m.ToolCalls {
				argsJSON, _ := json.Marshal(tc.Args)
				om.ToolCalls = append(om.ToolCalls, toolCall{
					ID:       tc.ID,
					Type:     "function",
					Function: functionCall{Name: string(tc.ToolID), Arguments: string(argsJSON)},
				})
			}
		}
		return om
	case llm.ToolMessage:
		return openaiMessage{
			Role:       "tool",
			Content:    m.Content,
			ToolCallID: m.ToolCallID,
		}
	default:
		return openaiMessage{
			Role:    "user",
			Content: "",
		}
	}
}

func contentToOpenAIContent(c llm.UserContent) interface{} {
	if len(c.Parts) == 0 {
		return ""
	}

	if len(c.Parts) == 1 {
		if tp, ok := c.Parts[0].(llm.TextPart); ok {
			return tp.Text
		}
	}

	parts := make([]map[string]interface{}, 0, len(c.Parts))
	for _, p := range c.Parts {
		switch v := p.(type) {
		case llm.TextPart:
			parts = append(parts, map[string]interface{}{
				"type": "text",
				"text": v.Text,
			})
		}
	}

	return parts
}

func openAIMessageToResult(msg openaiMessage) llm.Message {
	if len(msg.ToolCalls) > 0 {
		toolCalls := make([]llm.ToolCall, 0, len(msg.ToolCalls))
		for _, tc := range msg.ToolCalls {
			var args map[string]any
			_ = json.Unmarshal([]byte(tc.Function.Arguments), &args)
			toolCalls = append(toolCalls, llm.ToolCall{
				ID:     tc.ID,
				ToolID: llm.ToolID(tc.Function.Name),
				Args:   args,
			})
		}
		return llm.NewAssistantMessageWithToolCalls(toolCalls)
	}

	switch v := msg.Content.(type) {
	case string:
		return llm.NewAssistantMessage(v)
	case []interface{}:
		var textParts []string
		for _, p := range v {
			pm, ok := p.(map[string]interface{})
			if !ok {
				continue
			}
			switch pm["type"] {
			case "text":
				if text, ok := pm["text"].(string); ok {
					textParts = append(textParts, text)
				}
			}
		}
		if len(textParts) > 0 {
			return llm.NewAssistantMessage(strings.Join(textParts, ""))
		}
	}

	return llm.NewAssistantMessage("")
}
