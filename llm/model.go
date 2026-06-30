package llm

type ModelID string

type Model struct {
	ID          ModelID
	Name        string
	ContextSize int
}
