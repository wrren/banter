package llm

import (
	"github.com/wrren/banter/tools"
)

type Conversation struct {
	ProviderID ProviderID `json:"provider_id"`
	Session    *Session   `json:"session"`
}

func NewConversation(p ProviderID, s *Session) Conversation {
	return Conversation{
		ProviderID: p,
		Session:    s,
	}
}

// event is the sum type accepted on a running conversation's input channel.
// Go has no tagged unions, so we fake one with an unexported marker method -
// only this package can implement event, so a switch over its concrete
// types is exhaustive in practice.
type event interface {
	isEvent()
}

type userMessageEvent struct {
	message Message
}

func (userMessageEvent) isEvent() {}

type endEvent struct{}

func (endEvent) isEvent() {}

type completionResult struct {
	messages []Message
	err      error
}

// Handle is a running conversation's interface to the outside world. All
// conversation state is owned by a single goroutine (see Conversation.run);
// Handle only ever talks to it via channels, so Session is never touched
// from two goroutines at once.
type Handle struct {
	events chan event
	out    chan Message
	err    chan error
	done   chan struct{}
}

// Send queues a user message. If the model is currently generating a
// response the message is held and folded into the next completion once the
// in-flight one finishes; otherwise it's sent immediately.
func (h *Handle) Send(m Message) {
	h.events <- userMessageEvent{message: m}
}

// End stops the conversation. Any completion already in flight is left to
// finish in the background and its result discarded; queued messages that
// were never sent to the model are dropped.
func (h *Handle) End() {
	h.events <- endEvent{}
}

// Out streams messages produced by the model as each completion finishes.
// It's closed when the conversation ends, so callers can range over it.
func (h *Handle) Out() <-chan Message {
	return h.out
}

// Err streams errors encountered while completing the conversation. It's
// buffered so the run loop never blocks on a caller that isn't reading it.
func (h *Handle) Err() <-chan error {
	return h.err
}

// Done is closed once the conversation loop has exited.
func (h *Handle) Done() <-chan struct{} {
	return h.done
}

func (c *Conversation) StartConversation(providerRegistry ProviderRegistry, toolRegistry tools.ToolsRegistry) (*Handle, error) {
	p, ok := providerRegistry.GetProviderByID(c.ProviderID)
	if !ok {
		return nil, ErrProviderNotFound
	}

	h := &Handle{
		events: make(chan event, 8),
		out:    make(chan Message),
		err:    make(chan error, 1),
		done:   make(chan struct{}),
	}

	go c.run(p, h)

	return h, nil
}

func (c *Conversation) run(p Provider, h *Handle) {
	defer close(h.done)
	defer close(h.out)

	var (
		queue      []Message
		completing bool
		results    = make(chan completionResult, 1)
	)

	complete := func() {
		completing = true
		go func() {
			messages, err := p.Complete(c.Session)
			results <- completionResult{messages: messages, err: err}
		}()
	}

	for {
		select {
		case e := <-h.events:
			switch ev := e.(type) {
			case userMessageEvent:
				queue = append(queue, ev.message)
				if !completing {
					c.Session.Messages = append(c.Session.Messages, queue...)
					queue = nil
					complete()
				}
			case endEvent:
				return
			}

		case res := <-results:
			completing = false
			if res.err != nil {
				h.err <- res.err
				return
			}

			c.Session.Messages = append(c.Session.Messages, res.messages...)
			for _, m := range res.messages {
				h.out <- m
			}

			if len(queue) > 0 {
				c.Session.Messages = append(c.Session.Messages, queue...)
				queue = nil
				complete()
			}
		}
	}
}
