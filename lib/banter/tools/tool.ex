defmodule Banter.Tools.Tool do
  @moduledoc """
  Behaviour for tools that an LLM can call during a conversation.

  To install a new tool:

    1. Write a module implementing this behaviour.
    2. Add it to the `:tools` list in config, e.g.
       `config :banter, :tools, [MyApp.Tools.MyTool]`.

  The tool then appears in the UI where it can be enabled or disabled.
  Tools that should always be enabled and never shown in the UI (for
  example an internal "update the conversation title" tool) may implement
  the optional `hidden?/0` callback returning `true`.
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

  This callback receives only the decoded arguments. Tools that need
  run context (for example the active conversation) may instead define
  `execute/2`, which `Banter.Tools.execute/4` prefers when present.
  """
  @callback execute(args :: map()) :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Optional context-aware execution.

  `context` is a map supplied by the Runner; the current conversation is
  available under the `:conversation` key. Define this callback (in place
  of, or alongside, `execute/1`) when the tool needs run context. When a
  tool defines both, this callback wins.
  """
  @callback execute(args :: map(), context :: map()) ::
              {:ok, String.t()} | {:error, String.t()}

  @doc """
  Optional. Returns `true` when the tool should not appear in the UI tool
  panel. Hidden tools remain installed and enabled by default (they cannot
  be toggled from the UI), but are still sent to the LLM and can be
  executed. Defaults to `false` when not implemented.
  """
  @callback hidden?() :: boolean

  @optional_callbacks execute: 2, hidden?: 0
end
