package tools

import (
	"encoding/json"
	"fmt"
)

type ToolsRegistry struct {
	tools   map[string]Tool
	factory func(string, map[string]any) (Tool, error)
}

func NewToolsRegistry() *ToolsRegistry {
	return &ToolsRegistry{
		tools: make(map[string]Tool),
	}
}

func (r *ToolsRegistry) Register(t Tool) error {
	ider, ok := t.(interface{ ID() string })
	if !ok {
		return fmt.Errorf("tool does not implement ID() string")
	}
	id := ider.ID()
	if _, exists := r.tools[id]; exists {
		return fmt.Errorf("tool %q already registered", id)
	}
	r.tools[id] = t
	return nil
}

func (r *ToolsRegistry) Get(name string) (Tool, error) {
	t, ok := r.tools[name]
	if !ok {
		return nil, fmt.Errorf("tool %q not found in registry", name)
	}
	return t, nil
}

func (r *ToolsRegistry) Tools() map[string]Tool {
	return r.tools
}

func (r *ToolsRegistry) Names() []string {
	names := make([]string, 0, len(r.tools))
	for name := range r.tools {
		names = append(names, name)
	}
	return names
}

func (r *ToolsRegistry) SetFactory(f func(string, map[string]any) (Tool, error)) {
	r.factory = f
}

func (r *ToolsRegistry) MarshalJSON() ([]byte, error) {
	m := make(map[string]map[string]any, len(r.tools))
	for name, t := range r.tools {
		m[name] = t.Config()
	}
	return json.Marshal(m)
}

func (r *ToolsRegistry) UnmarshalJSON(data []byte) error {
	var m map[string]map[string]any
	if err := json.Unmarshal(data, &m); err != nil {
		return err
	}
	for name, config := range m {
		if r.factory == nil {
			return fmt.Errorf("no factory set on ToolsRegistry")
		}
		t, err := r.factory(name, config)
		if err != nil {
			return err
		}
		r.tools[name] = t
	}
	return nil
}
