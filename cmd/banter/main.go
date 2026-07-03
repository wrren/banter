package main

import (
	"bufio"
	"fmt"
	"os"

	"charm.land/glamour/v2"
	"github.com/wrren/banter/config"
	"github.com/wrren/banter/llm"
	"github.com/wrren/banter/tools"

	_ "github.com/wrren/banter/llm/providers"
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

	registry, err := llm.NewRegistry(cfg.Providers)
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
	toolRegistry := tools.NewToolsRegistry()
	toolRegistry.Register(tools.NewBraveSearch(os.Getenv("BRAVE_SEARCH_API_KEY")))
	toolRegistry.SetFactory(func(name string, config map[string]any) (tools.Tool, error) {
		switch name {
		case "brave_search":
			key, _ := config["api_key"].(string)
			return tools.NewBraveSearch(key), nil
		default:
			return nil, fmt.Errorf("unknown tool: %s", name)
		}
	})

	session := &llm.Session{
		ModelID:  model,
		Prompt:   systemPrompt,
		Messages: []llm.Message{},
		Tools:    *toolRegistry,
	}

	reader := bufio.NewReader(os.Stdin)

	for {
		fmt.Print("> ")

		msg, err := reader.ReadString('\n')
		if err != nil {
			fmt.Printf("error while reading from stdin: %v\n", err)
			os.Exit(1)
		}

		session.AppendUserTextMessage(msg)

		messages, err := provider.Complete(session)
		if err != nil {
			fmt.Printf("error during chat completion: %v\n", err)
			os.Exit(1)
		}

		for _, m := range messages {
			switch msg := m.(type) {
			case llm.AssistantMessage:
				if msg.Content != nil {
					out, err := glamour.Render(*msg.Content, "dark")
					if err == nil {
						fmt.Println(out)
					}
				}
			}
		}

		session.Messages = append(session.Messages, messages...)
	}
}
