defmodule Banter.Tools.Tool do
  @moduledoc """
  Behaviour for tools that an LLM can call during a conversation.

  To install a new tool:

    1. Write a module implementing this behaviour.
    2. Add it to the `:tools` list in config, e.g.
       `config :banter, :tools, [MyApp.Tools.MyTool]`.

  The tool then appears in the UI where it can be enabled or disabled.
  """

  @doc "The unique tool name, as sent to and received from the LLM."
  @callback name() :: String.t()

  @doc "A description of the tool, shown to the LLM."
  @callback description() :: String.t()

  @doc "A JSON Schema map describing the tool's arguments."
  @callback parameters() :: map()

  @doc """
  Executes the tool with the decoded JSON arguments provided by the LLM.

  The returned string is sent back to the LLM as the tool result, so
  prefer compact representations that minimise token usage.
  """
  @callback execute(args :: map()) :: {:ok, String.t()} | {:error, String.t()}
end
