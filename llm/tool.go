package llm

type ToolID string

type Tool struct {
	ID        ToolID         `json:"id"`
	Name      string         `json:"name"`
	ArgSchema map[string]any `json:"arg_schema"`
}

type ToolCall struct {
	ID     string         `json:"id"`
	ToolID ToolID         `json:"tool_id"`
	Args   map[string]any `json:"args"`
}

type ToolResult struct {
	ToolCallID string         `json:"tool_call_id"`
	Succeeded  bool           `json:"succeeded"`
	Result     map[string]any `json:"result"`
}
