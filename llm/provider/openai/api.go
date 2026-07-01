package openai

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/wrren/banter/llm"
)

type openaiMessage struct {
	Role      string          `json:"role"`
	Content   interface{}     `json:"content"`
	Name      string          `json:"name,omitempty"`
	ToolCalls []toolCall      `json:"tool_calls,omitempty"`
	ToolCallID string         `json:"tool_call_id,omitempty"`
}

type toolCall struct {
	ID       string        `json:"id"`
	Type     string        `json:"type"`
	Function functionCall  `json:"function"`
}

type functionCall struct {
	Name      string `json:"name"`
	Arguments string `json:"arguments"`
}

type openaiTool struct {
	Type     string        `json:"type"`
	Function openaiFunction `json:"function"`
}

type openaiFunction struct {
	Name        string                 `json:"name"`
	Description string                 `json:"description,omitempty"`
	Parameters  map[string]interface{} `json:"parameters"`
}

type chatCompletionRequest struct {
	Model    string      `json:"model"`
	Messages []openaiMessage `json:"messages"`
	Tools    []openaiTool    `json:"tools,omitempty"`
	ToolChoice interface{} `json:"tool_choice,omitempty"`
}

type chatCompletionResponse struct {
	ID      string   `json:"id"`
	Object  string   `json:"object"`
	Created int64    `json:"created"`
	Model   string   `json:"model"`
	Choices []choice `json:"choices"`
	Error   *apiError `json:"error,omitempty"`
}

type choice struct {
	Index        int             `json:"index"`
	Message      openaiMessage   `json:"message"`
	FinishReason string          `json:"finish_reason"`
	LogProbs     interface{}     `json:"logprobs"`
}

type apiError struct {
	Message string `json:"message"`
	Type    string `json:"type"`
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

	var tools []openaiTool
	if len(session.Tools) > 0 {
		tools = make([]openaiTool, 0, len(session.Tools))
		for _, tool := range session.Tools {
			tools = append(tools, openaiTool{
				Type: "function",
				Function: openaiFunction{
					Name:       tool.Name,
					Parameters: tool.ArgSchema,
				},
			})
		}
	}

	reqBody := chatCompletionRequest{
		Model:    string(session.ModelID),
		Messages: messages,
		Tools:    tools,
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
	switch msg.Source {
	case llm.MessageSourceUser:
		return openaiMessage{
			Role:    "user",
			Content: contentToInterface(msg.Content),
		}
	case llm.MessageSourceAgent:
		return openaiMessage{
			Role:    "assistant",
			Content: contentToInterface(msg.Content),
		}
	case llm.MessageSourceToolResult:
		return openaiMessage{
			Role:    "tool",
			Content: contentToInterface(msg.Content),
		}
	default:
		return openaiMessage{
			Role:    "user",
			Content: contentToInterface(msg.Content),
		}
	}
}

func contentToInterface(c llm.Content) interface{} {
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
		case llm.ImagePart:
			parts = append(parts, map[string]interface{}{
				"type": "image_url",
				"image_url": map[string]interface{}{
					"url": fmt.Sprintf("data:image/jpeg;base64,%s", v.Base64Content),
				},
			})
		}
	}

	return parts
}

func openAIMessageToResult(msg openaiMessage) llm.Message {
	result := llm.Message{
		Source: llm.MessageSourceAgent,
	}

	if msg.Content != nil {
		switch v := msg.Content.(type) {
		case string:
			result.Content.Parts = []llm.ContentPart{llm.TextPart{Type: "text", Text: v}}
		case []interface{}:
			for _, p := range v {
				pm, ok := p.(map[string]interface{})
				if !ok {
					continue
				}
				switch pm["type"] {
				case "text":
					if text, ok := pm["text"].(string); ok {
						result.Content.Parts = append(result.Content.Parts, llm.TextPart{Type: "text", Text: text})
					}
				case "image_url":
					img, ok := pm["image_url"].(map[string]interface{})
					if !ok {
						continue
					}
					if url, ok := img["url"].(string); ok {
						result.Content.Parts = append(result.Content.Parts, llm.ImagePart{Type: "image_url", Base64Content: url})
					}
				}
			}
		}
	}

	return result
}
