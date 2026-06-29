package config

import (
	"fmt"
	"os"
	"path"

	"github.com/pkg/errors"
	yaml "gopkg.in/yaml.v3"
)

type ProviderConfig struct {
	Type    string                 `yaml:"type" json:"type"`
	Name    string                 `yaml:"name" json:"name"`
	APIKey  string                 `yaml:"api_key" json:"api_key"`
	Options map[string]interface{} `yaml:"options" json:"options"`
}

type Config struct {
	Providers []ProviderConfig `yaml:"providers" json:"providers"`
}

func Load() (*Config, error) {
	cfg := Config{
		Providers: make([]ProviderConfig, 0),
	}

	home, err := os.UserHomeDir()
	if err != nil {
		return nil, errors.Wrap(err, "unable to determine user home directory")
	}

	configPath := path.Join(home, ".config", "banter", "config.yaml")
	stat, err := os.Stat(configPath)
	if err != nil {
		return nil, errors.Wrap(err, "unable to stat banter config file")
	}
	if stat.IsDir() {
		return nil, fmt.Errorf("config file path %s is a directory", configPath)
	}

	content, err := os.ReadFile(configPath)
	if err != nil {
		return nil, errors.Wrap(err, "cannot read config file")
	}

	err = yaml.Unmarshal(content, &cfg)
	if err != nil {
		return nil, errors.Wrap(err, "cannot unmarshal config file")
	}

	return &cfg, nil
}
