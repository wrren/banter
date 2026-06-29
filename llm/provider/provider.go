package provider

import (
	"github.com/wrren/banter/config"
	"github.com/wrren/banter/llm"
	"github.com/wrren/banter/llm/provider/llamacpp"
)

type Provider interface {
	ListModels() ([]llm.Model, error)
}

type ProviderRegistry struct {
	Providers map[string]Provider
}

func NewRegistry(cfg []config.ProviderConfig) (*ProviderRegistry, error) {
	registry := ProviderRegistry{
		Providers: make(map[string]Provider),
	}

	for _, p := range cfg {
		switch p.Type {
		case llamacpp.ProviderType:
			provider, err := llamacpp.NewProvider(p)
			if err != nil {
				return nil, err
			}
			registry.Providers[p.Name] = provider
		}
	}

	return &registry, nil
}
