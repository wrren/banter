package main

import (
	"bufio"
	"fmt"
	"os"

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
		ModelID:  model,
		Prompt:   systemPrompt,
		Messages: []llm.Message{},
	}

	reader := bufio.NewReader(os.Stdin)

	for {
		fmt.Print("> ")

		msg, err := reader.ReadString('\n')
		if err != nil {
			fmt.Printf("error while reading from stdin: %v\n", err)
			os.Exit(1)
		}

		session.Messages = append(session.Messages, llm.Message{
			Source: llm.MessageSourceUser,
			Content: llm.Content{
				Parts: []llm.ContentPart{
					llm.TextPart{
						Type: "text",
						Text: msg,
					},
				},
			},
		})

		messages, err := provider.Complete(session)
		if err != nil {
			fmt.Printf("error during chat completion: %v\n", err)
			os.Exit(1)
		}

		for _, m := range messages {
			for _, p := range m.Content.Parts {
				switch x := p.(type) {
				case llm.TextPart:
					fmt.Printf("\n\033[33m%s\033[0m\n\n", x.Text)
				}
			}
		}

		session.Messages = append(session.Messages, messages...)
	}
}
