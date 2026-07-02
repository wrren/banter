package conversation

import (
	"fmt"
	"os"

	"github.com/wrren/banter/llm"
	"github.com/wrren/banter/llm/provider"
	"github.com/wrren/banter/tools"
)

type Conversation struct {
	ProviderID provider.ProviderID `json:"provider_id"`
	Session    *llm.Session        `json:"session"`
}

func NewConversation(p provider.ProviderID, s *llm.Session) Conversation {
	return Conversation{
		ProviderID: p,
		Session:    s,
	}
}

func (c *Conversation) StartConversation(providerRegistry provider.ProviderRegistry, toolRegistry tools.ToolsRegistry) (chan llm.Message, error) {
	channel := make(chan llm.Message)

	p, ok := providerRegistry.GetProviderByID(c.ProviderID)
	if !ok {
		return nil, provider.ErrProviderNotFound
	}

	go func() {
		for m := range channel {
			c.Session.Messages = append(c.Session.Messages, m)

			messages, err := p.Complete(c.Session)
			if err != nil {
				fmt.Printf("error during chat completion: %v\n", err)
				os.Exit(1)
			}

		}
	}()

	return channel, nil
}
