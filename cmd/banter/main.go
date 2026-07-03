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

	model := llm.ModelID("ornith-35b")
	toolRegistry := tools.NewToolsRegistry()
	toolRegistry.Register(tools.NewBraveSearch(os.Getenv("BRAVE_SEARCH_API_KEY")))
	toolRegistry.Register(tools.NewWebFetch())
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

	conversation := llm.NewConversation("barbatos", session)
	handle, err := conversation.StartConversation(registry, toolRegistry)
	if err != nil {
		fmt.Printf("error while starting conversation: %v\n", err)
		os.Exit(1)
	}

	msg := ""
	if len(os.Args) > 1 {
		msg = os.Args[1]
	}

	go func() {
		for {
			fmt.Print("> ")
			msg, err = reader.ReadString('\n')
			if err != nil {
				fmt.Printf("error while reading from stdin: %v\n", err)
				handle.End()
				return
			}
			handle.Send(llm.NewUserMessage(msg))
		}
	}()

	for m := range handle.Out() {
		switch msg := m.(type) {
		case llm.AssistantMessage:
			if msg.Content != nil {
				out, err := glamour.Render(*msg.Content, "dark")
				if err == nil {
					fmt.Println(out)
				}
			}
			if len(msg.ToolCalls) > 0 {
				for _, tc := range msg.ToolCalls {
					fmt.Printf("Agent invoked tool %s\n", tc.ToolID)
				}
			}
		}
	}

	for e := range handle.Err() {
		fmt.Printf("error during conversation: %v\n", e)
		os.Exit(1)
	}
}
