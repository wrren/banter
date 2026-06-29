package main

import (
	"fmt"
	"os"

	"github.com/wrren/banter/config"
	"github.com/wrren/banter/llm/provider"
)

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

	for n, p := range registry.Providers {
		models, err := p.ListModels()
		if err != nil {
			fmt.Printf("error while listing models for provider %s: %v", n, err)
			os.Exit(1)
		}
		fmt.Println(n)
		for _, m := range models {
			fmt.Printf("\tModel %s (%s): %d\n", m.ID, m.Name, m.ContextSize)
		}
	}
}
