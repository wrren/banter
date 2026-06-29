package llamacpp

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"

	"github.com/pkg/errors"
	"github.com/wrren/banter/config"
	"github.com/wrren/banter/core"
	"github.com/wrren/banter/llm"
)

const (
	ProviderType       = "llama-cpp"
	DefaultContextSize = 64536
	baseURLKey         = "base_url"
)

var (
	ErrNoBaseURL      = errors.New("no base url specified in provider options")
	ErrInvalidBaseURL = errors.New("invalid base url specified in provider options")
)

type ModelStatus struct {
	Value string   `json:"value"`
	Args  []string `json:"args"`
}

func (m ModelStatus) GetContextSize(defaultSize int) int {
	for i, a := range m.Args {
		if a == "--ctx-size" {
			if (i + 1) < len(m.Args) {
				size, err := strconv.Atoi(m.Args[i+1])
				if err == nil {
					return size
				}
			}
			return defaultSize
		}
	}

	return defaultSize
}

type Model struct {
	ID      string      `json:"id"`
	Aliases []string    `json:"aliases"`
	Tags    []string    `json:"tags"`
	OwnedBy string      `json:"owned_by"`
	Created int         `json:"created"`
	Status  ModelStatus `json:"status"`
}

type ModelsResponse struct {
	Data []Model `json:"data"`
}

type Provider struct {
	baseURL string
}

func NewProvider(cfg config.ProviderConfig) (*Provider, error) {
	baseURL, ok := cfg.Options[baseURLKey]
	if !ok {
		return nil, ErrNoBaseURL
	}

	baseURLString, ok := baseURL.(string)
	if !ok {
		return nil, ErrInvalidBaseURL
	}

	if _, err := url.Parse(baseURLString); err != nil {
		return nil, errors.Wrap(err, "invalid base url specifid in provider options")
	}

	return &Provider{
		baseURL: baseURLString,
	}, nil
}

func (p *Provider) ListModels() ([]llm.Model, error) {
	res, err := http.Get(p.baseURL + "/v1/models")
	if err != nil {
		return nil, err
	}

	if res.StatusCode != 200 {
		return nil, fmt.Errorf("received unexpected status code from llama.cpp server: %d", res.StatusCode)
	}

	defer res.Body.Close()

	body, err := io.ReadAll(res.Body)
	if err != nil {
		return nil, errors.Wrap(err, "failed to read llama.cpp response body")
	}

	var modelsResponse ModelsResponse

	err = json.Unmarshal(body, &modelsResponse)
	if err != nil {
		return nil, errors.Wrap(err, "failed to unmarshal llama.cpp response body")
	}

	models := make([]llm.Model, 0, len(modelsResponse.Data))
	for _, m := range modelsResponse.Data {
		models = append(models, llm.Model{
			ID:          m.ID,
			Name:        core.FirstOrDefault(m.Aliases, m.ID),
			ContextSize: m.Status.GetContextSize(DefaultContextSize),
		})
	}

	return models, nil
}
