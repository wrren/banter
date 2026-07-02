package tools

import (
	"context"
)

type ArgsSchema struct {
	Type                 string         `json:"type"`
	Properties           map[string]any `json:"properties"`
	Required             []string       `json:"required"`
	AdditionalProperties bool           `json:"additionalProperties"`
}

type Tool interface {
	Invoke(ctx context.Context, args map[string]any) (any, error)
	Description() string
	ArgsSchema() ArgsSchema
	Config() map[string]any
}
