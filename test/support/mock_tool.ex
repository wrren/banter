defmodule Banter.Tools.MockTool do
  @moduledoc """
  A mock tool for tests. Records every execution and can be scripted to
  return a fixed result.

  Like `Banter.LLM.Mock`, this is backed by a global agent, so tests that
  use it must run with `async: false`.
  """

  @behaviour Banter.Tools.Tool

  @name __MODULE__

  def start do
    Agent.start(fn -> %{result: {:ok, "mock tool result"}, calls: []} end, name: @name)
  end

  @doc "Sets the result returned by `execute/1` and clears recorded calls."
  def set_result(result) do
    Agent.update(@name, fn state -> %{state | result: result, calls: []} end)
  end

  @doc "Returns the list of argument maps the tool was executed with."
  def calls do
    @name |> Agent.get(& &1.calls) |> Enum.reverse()
  end

  @impl true
  def name, do: "mock_tool"

  @impl true
  def description, do: "A mock tool used in tests."

  @impl true
  def parameters do
    %{
      "type" => "object",
      "properties" => %{"input" => %{"type" => "string"}},
      "required" => ["input"]
    }
  end

  @impl true
  def execute(args) do
    Agent.update(@name, fn state -> %{state | calls: [args | state.calls]} end)
    Agent.get(@name, & &1.result)
  end
end
