package provider

import (
	"errors"

	"github.com/wrren/banter/config"
	"github.com/wrren/banter/llm"
	"github.com/wrren/banter/llm/provider/llamacpp"
)

type ProviderID string

var ErrProviderNotFound = errors.New("provider not found")

type Provider interface {
	ListModels() ([]llm.Model, error)
	Complete(session *llm.Session) ([]llm.Message, error)
}

type ProviderRegistry struct {
	Providers map[ProviderID]Provider
}

func NewRegistry(cfg []config.ProviderConfig) (*ProviderRegistry, error) {
	registry := ProviderRegistry{
		Providers: make(map[ProviderID]Provider),
	}

	for _, p := range cfg {
		switch p.Type {
		case llamacpp.ProviderType:
			provider, err := llamacpp.NewProvider(p)
			if err != nil {
				return nil, err
			}
			registry.Providers[ProviderID(p.Name)] = provider
		}
	}

	return &registry, nil
}

func (p ProviderRegistry) GetProviderByID(id ProviderID) (Provider, bool) {
	provider, ok := p.Providers[id]
	return provider, ok
}
