defmodule Banter.Tools do
  @moduledoc """
  The Tools context: a registry of installed tools with per-tool
  enabled state persisted in the database.

  Tools are *installed* by adding their module to the `:tools` config list
  and *enabled/disabled* at runtime, e.g. from the UI:

      config :banter, :tools, [Banter.Tools.WebSearch, Banter.Tools.WebFetch]
  """

  alias Banter.Repo
  alias Banter.Tools.ToolState

  @pubsub Banter.PubSub
  @topic "tools"

  @doc """
  Subscribes to tool state changes.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  @doc """
  Returns the list of installed tool modules.
  """
  def available do
    Application.get_env(:banter, :tools, [])
  end

  @doc """
  Lists installed tools together with their enabled state, as maps:

      %{module: module, name: binary, description: binary, enabled: boolean}
  """
  def list do
    states = Map.new(Repo.all(ToolState), &{&1.name, &1.enabled})

    for module <- available() do
      name = module.name()

      %{
        module: module,
        name: name,
        description: module.description(),
        enabled: Map.get(states, name, true)
      }
    end
  end

  @doc """
  Returns true if the named tool is installed and enabled.
  """
  def enabled?(name) do
    with {:ok, _module} <- fetch_tool(name) do
      case Repo.get_by(ToolState, name: name) do
        nil -> true
        %ToolState{enabled: enabled} -> enabled
      end
    else
      _ -> false
    end
  end

  @doc """
  Enables or disables an installed tool, broadcasting the change.
  """
  def set_enabled(name, enabled) when is_boolean(enabled) do
    with {:ok, _module} <- fetch_tool(name) do
      %ToolState{name: name}
      |> ToolState.changeset(%{name: name, enabled: enabled})
      |> Repo.insert(
        on_conflict: [
          set: [enabled: enabled, updated_at: DateTime.truncate(DateTime.utc_now(), :second)]
        ],
        conflict_target: :name
      )
      |> case do
        {:ok, state} ->
          Phoenix.PubSub.broadcast(@pubsub, @topic, {:tool_toggled, state})
          {:ok, state}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Returns the OpenAI-format tool specs for all enabled tools.
  """
  def enabled_specs do
    for %{enabled: true} = tool <- list() do
      %{
        "type" => "function",
        "function" => %{
          "name" => tool.name,
          "description" => tool.description,
          "parameters" => tool.module.parameters()
        }
      }
    end
  end

  @doc """
  Executes the named tool with the given (already JSON-decoded) arguments.

  Returns `{:ok, result}` or `{:error, message}`; the message is suitable
  for sending back to the LLM as the tool result.
  """
  def execute(name, args) when is_map(args) do
    with {:ok, module} <- fetch_tool(name),
         :ok <- ensure_enabled(name) do
      try do
        module.execute(args)
      rescue
        exception -> {:error, "tool #{name} crashed: #{Exception.message(exception)}"}
      end
    end
  end

  defp fetch_tool(name) do
    case Enum.find(available(), fn module -> module.name() == name end) do
      nil -> {:error, "unknown tool: #{name}"}
      module -> {:ok, module}
    end
  end

  defp ensure_enabled(name) do
    if enabled?(name), do: :ok, else: {:error, "tool #{name} is disabled"}
  end
end
