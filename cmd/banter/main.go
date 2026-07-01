package main

import (
	"fmt"
	"os"
	"strings"

	"github.com/wrren/banter/config"
	"github.com/wrren/banter/llm"
	"github.com/wrren/banter/llm/provider"
)

var systemPrompt llm.SystemPrompt = llm.SystemPrompt{
	Content: "You are a helpful assistant",
}

func main() {
	cfg, err := config.Load()
	if err != nil {
		fmt.Printf("error while loading configuration: %v", err)
		os.Exit(1)
	}

	if len(os.Args) < 2 {
		fmt.Println("please submit a query")
		os.Exit(1)
	}

	sb := strings.Builder{}
	for i, t := range os.Args {
		if i == 0 {
			continue
		}
		sb.WriteString(" ")
		sb.WriteString(t)
	}

	registry, err := provider.NewRegistry(cfg.Providers)
	if err != nil {
		fmt.Printf("error while loading provider registry: %v", err)
		os.Exit(1)
	}

	provider, ok := registry.GetProviderByID("barbatos")
	if !ok {
		fmt.Println("failed to find provider")
		os.Exit(1)
	}

	model := llm.ModelID("ornith-35b")

	session := &llm.Session{
		ModelID: model,
		Prompt:  systemPrompt,
		Messages: []llm.Message{
			{
				Source: llm.MessageSourceUser,
				Content: llm.Content{
					Parts: []llm.ContentPart{
						llm.TextPart{Type: "text", Text: sb.String()},
					},
				},
			},
		},
	}

	messages, err := provider.Complete(session)
	if err != nil {
		fmt.Printf("error during chat completion: %v\n", err)
		os.Exit(1)
	}

	for _, m := range messages {
		for _, p := range m.Content.Parts {
			switch x := p.(type) {
			case llm.TextPart:
				fmt.Println(x.Text)
			}
		}
	}
}
