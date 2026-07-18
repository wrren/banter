defmodule Banter.LLM.SSETest do
  use ExUnit.Case, async: true

  alias Banter.LLM.SSE

  test "parses a single complete event" do
    assert {["hello"], ""} = SSE.feed("", "data: hello\n\n")
  end

  test "buffers an incomplete event" do
    assert {[], "data: hel"} = SSE.feed("", "data: hel")
  end

  test "parses an event split across chunks" do
    {[], rest} = SSE.feed("", "data: hel")
    assert {["hello"], ""} = SSE.feed(rest, "lo\n\n")
  end

  test "parses multiple events in one chunk" do
    assert {["one", "two"], ""} = SSE.feed("", "data: one\n\ndata: two\n\n")
  end

  test "keeps a trailing partial event in the buffer" do
    assert {["one"], "data: tw"} = SSE.feed("", "data: one\n\ndata: tw")
  end

  test "handles CRLF line endings" do
    assert {["hello"], ""} = SSE.feed("", "data: hello\r\n\r\n")
  end

  test "handles a CRLF boundary split across chunks" do
    {[], rest} = SSE.feed("", "data: hi\r\n\r")
    assert {["hi"], ""} = SSE.feed(rest, "\n")
  end

  test "joins multi-line data payloads" do
    assert {["line1\nline2"], ""} = SSE.feed("", "data: line1\ndata: line2\n\n")
  end

  test "ignores comments and other fields" do
    assert {["ok"], ""} = SSE.feed("", ": keep-alive\nevent: message\nid: 1\ndata: ok\n\n")
  end

  test "passes through the [DONE] sentinel" do
    assert {["[DONE]"], ""} = SSE.feed("", "data: [DONE]\n\n")
  end

  test "parses a realistic OpenAI stream" do
    chunk1 =
      ~s(data: {"choices":[{"delta":{"role":"assistant"}}]}\n\ndata: {"choices":[{"delta":{"content":"Hel)

    chunk2 = ~s(lo"}}]}\n\ndata: [DONE]\n\n)

    {events1, rest} = SSE.feed("", chunk1)
    {events2, ""} = SSE.feed(rest, chunk2)

    assert [role_event] = events1
    assert %{"choices" => [%{"delta" => %{"role" => "assistant"}}]} = Jason.decode!(role_event)

    assert [content_event, "[DONE]"] = events2
    assert %{"choices" => [%{"delta" => %{"content" => "Hello"}}]} = Jason.decode!(content_event)
  end
end
