defmodule Banter.LLM.Provider do
  @moduledoc """
  Behaviour for LLM providers that power conversations.

  A provider receives a list of messages in the OpenAI chat completions
  shape and returns the final assistant message in the same shape:

      {:ok, message(), usage()}

  ## Options

    * `:model` - the model id to use
    * `:tools` - OpenAI-format tool specs the model may call
    * `:stream_to` - a pid that receives `{:llm_text_delta, text}` for
      every streamed text fragment
    * `:base_url` - override the provider's configured base URL (used
      for database-backed providers)
    * `:api_key` - override the provider's configured API key (used
      for database-backed providers)
  """

  @type message :: %{String.t() => term()}

  @type usage :: %{
          optional(:prompt_tokens) => non_neg_integer(),
          optional(:completion_tokens) => non_neg_integer(),
          optional(:total_tokens) => non_neg_integer()
        }

  @callback chat(messages :: [message()], opts :: keyword()) ::
              {:ok, message(), usage()} | {:error, term()}
end
