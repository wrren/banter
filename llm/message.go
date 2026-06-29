package llm

type MessageSource int

const (
	MessageSourceUser       MessageSource = iota
	MessageSourceAgent      MessageSource = iota
	MessageSourceToolResult MessageSource = iota
)

type SystemPrompt struct {
	Content string `json:"content"`
}

type Message struct {
	Source  MessageSource `json:"source"`
	Content string        `json:"content"`
}
