defmodule Banter.LLM.Provider do
  @moduledoc """
  Behaviour for LLM providers that power conversations.

  A provider receives a list of messages in the OpenAI chat completions
  shape and returns the final assistant message in the same shape:

      {:ok, %{"role" => "assistant", "content" => "...", "tool_calls" => nil}}

  ## Options

    * `:model` - the model id to use
    * `:tools` - OpenAI-format tool specs the model may call
    * `:stream_to` - a pid that receives `{:llm_text_delta, text}` for
      every streamed text fragment
  """

  @type message :: %{String.t() => term()}

  @callback chat(messages :: [message()], opts :: keyword()) ::
              {:ok, message()} | {:error, term()}
end
