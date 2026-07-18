defmodule Banter.LLM do
  @moduledoc """
  Facade for the configured LLM provider.

  The provider module is set via `config :banter, :llm_provider` and must
  implement the `Banter.LLM.Provider` behaviour.
  """

  @doc """
  Returns the configured provider module.
  """
  def provider do
    Application.get_env(:banter, :llm_provider, Banter.LLM.OpenAI)
  end

  @doc """
  Sends messages (OpenAI format) to the provider. See
  `Banter.LLM.Provider.chat/2` for the available options.
  """
  def chat(messages, opts \\ []) do
    provider().chat(messages, opts)
  end

  @doc """
  The default model id for new conversations.
  """
  def default_model do
    provider_config()[:model]
  end

  @doc """
  The list of models offered by the UI selector. Falls back to just the
  default model when no explicit list is configured.
  """
  def available_models do
    case provider_config()[:models] do
      models when is_list(models) and models != [] -> models
      _ -> List.wrap(default_model())
    end
  end

  defp provider_config do
    Application.get_env(:banter, provider(), [])
  end
end
