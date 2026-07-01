package llm

import "encoding/json"

type MessageSource int

const (
	MessageSourceUser       MessageSource = iota
	MessageSourceAgent      MessageSource = iota
	MessageSourceToolResult MessageSource = iota
)

type ContentPart interface {
	isContentPart()
}

type TextPart struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

func (t TextPart) isContentPart() {}

type ImagePart struct {
	Type          string `json:"type"`
	Base64Content string `json:"image"`
}

func (i ImagePart) isContentPart() {}

type Content struct {
	Parts []ContentPart
}

func (c *Content) UnmarshalJSON(data []byte) error {
	var s string
	if err := json.Unmarshal(data, &s); err == nil {
		c.Parts = []ContentPart{TextPart{Type: "text", Text: s}}
		return nil
	}

	c.Parts = make([]ContentPart, 0)
	var raw []json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}

	for _, r := range raw {
		var probe struct {
			Type string `json:"type"`
		}

		if err := json.Unmarshal(r, &probe); err != nil {
			return err
		}

		switch probe.Type {
		case "text":
			var p TextPart
			if err := json.Unmarshal(r, &p); err != nil {
				return err
			}
			c.Parts = append(c.Parts, p)

		case "image":
			var i ImagePart
			if err := json.Unmarshal(r, &i); err != nil {
				return err
			}
			c.Parts = append(c.Parts, i)
		}
	}

	return nil
}

func (c Content) MarshalJSON() ([]byte, error) {
	if len(c.Parts) == 1 {
		if tp, ok := c.Parts[0].(TextPart); ok {
			return json.Marshal(tp.Text)
		}
	}

	return json.Marshal(c.Parts)
}

type Message struct {
	Source  MessageSource `json:"source"`
	Content Content       `json:"content"`
}
