package llm

import (
	"errors"

	"github.com/wrren/banter/config"
)

type ProviderID string

var ErrProviderNotFound = errors.New("provider not found")

type ProviderConstructor func(cfg *config.ProviderConfig) (Provider, error)

var Providers map[string]ProviderConstructor = make(map[string]ProviderConstructor)

type Provider interface {
	ListModels() ([]Model, error)
	Complete(session *Session) ([]Message, error)
}

type ProviderRegistry struct {
	Providers map[ProviderID]Provider
}

func NewRegistry(cfg []config.ProviderConfig) (*ProviderRegistry, error) {
	registry := ProviderRegistry{
		Providers: make(map[ProviderID]Provider),
	}

	for _, p := range cfg {
		constructor, ok := Providers[p.Type]
		if !ok {
			return nil, ErrProviderNotFound
		}

		provider, err := constructor(&p)
		if err != nil {
			return nil, err
		}
		registry.Providers[ProviderID(p.Name)] = provider
	}

	return &registry, nil
}

func (p ProviderRegistry) GetProviderByID(id ProviderID) (Provider, bool) {
	provider, ok := p.Providers[id]
	return provider, ok
}
