defmodule Banter.LLM.OpenAITest do
  use ExUnit.Case, async: true

  alias Banter.LLM.OpenAI

  defp stub_stream(handler) do
    Req.Test.stub(Banter.LLM.OpenAI, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      handler.(conn, Jason.decode!(body))
    end)
  end

  defp sse(events) do
    Enum.map_join(events ++ ["[DONE]"], "", &"data: #{&1}\n\n")
  end

  test "streams text deltas and returns the assembled message" do
    stub_stream(fn conn, request ->
      assert request["model"] == "test-model"
      assert request["stream"] == true
      assert request["messages"] == [%{"role" => "user", "content" => "hi"}]
      refute Map.has_key?(request, "tools")

      conn
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.send_resp(
        200,
        sse([
          ~s({"choices":[{"delta":{"role":"assistant"}}]}),
          ~s({"choices":[{"delta":{"content":"Hello"}}]}),
          ~s({"choices":[{"delta":{"content":" world"}}]}),
          ~s({"choices":[{"delta":{},"finish_reason":"stop"}]})
        ])
      )
    end)

    assert {:ok, message} =
             OpenAI.chat([%{"role" => "user", "content" => "hi"}], stream_to: self())

    assert message == %{"role" => "assistant", "content" => "Hello world", "tool_calls" => nil}
    assert_received {:llm_text_delta, "Hello"}
    assert_received {:llm_text_delta, " world"}
  end

  test "sends tool specs and assembles streamed tool calls" do
    tools = [
      %{
        "type" => "function",
        "function" => %{"name" => "web_search", "parameters" => %{"type" => "object"}}
      }
    ]

    stub_stream(fn conn, request ->
      assert request["tools"] == tools

      conn
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.send_resp(
        200,
        sse([
          ~s({"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"web_search","arguments":""}}]}}]}),
          ~s({"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"query\\":"}}]}}]}),
          ~s({"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"elixir\\"}"}}]}}]}),
          ~s({"choices":[{"delta":{},"finish_reason":"tool_calls"}]})
        ])
      )
    end)

    assert {:ok, message} = OpenAI.chat([], tools: tools, stream_to: self())

    assert %{
             "role" => "assistant",
             "content" => nil,
             "tool_calls" => [
               %{
                 "id" => "call_1",
                 "type" => "function",
                 "function" => %{"name" => "web_search", "arguments" => ~s({"query":"elixir"})}
               }
             ]
           } = message

    refute_received {:llm_text_delta, _}
  end

  test "assembles multiple tool calls in index order" do
    stub_stream(fn conn, _request ->
      conn
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.send_resp(
        200,
        sse([
          ~s({"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_a","type":"function","function":{"name":"one","arguments":"{}"}}]}}]}),
          ~s({"choices":[{"delta":{"tool_calls":[{"index":1,"id":"call_b","type":"function","function":{"name":"two","arguments":"{}"}}]}}]})
        ])
      )
    end)

    assert {:ok, message} = OpenAI.chat([], stream_to: self())

    assert %{"tool_calls" => [first, second]} = message
    assert first["id"] == "call_a"
    assert second["id"] == "call_b"
  end

  test "returns a useful error on HTTP failure" do
    stub_stream(fn conn, _request ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(401, ~s({"error":{"message":"invalid api key"}}))
    end)

    assert {:error, message} = OpenAI.chat([], stream_to: self())
    assert message =~ "HTTP 401"
    assert message =~ "invalid api key"
  end

  test "uses the model from options over config" do
    stub_stream(fn conn, request ->
      assert request["model"] == "other-model"

      conn
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.send_resp(200, sse([]))
    end)

    assert {:ok, _} = OpenAI.chat([], model: "other-model", stream_to: self())
  end
end
