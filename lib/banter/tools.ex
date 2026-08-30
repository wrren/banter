defmodule Banter.Tools do
  @moduledoc """
  The Tools context: a registry of installed tools with per-tool
  enabled state persisted in the database.

  Tools are *installed* by adding their module to the `:tools` config list
  and *enabled/disabled* at runtime, e.g. from the UI:

      config :banter, :tools, [Banter.Tools.WebSearch, Banter.Tools.WebFetch]
  """

  import Ecto.Query, warn: false

  alias Banter.Repo
  alias Banter.Tools.ToolState

  @pubsub Banter.PubSub

  @doc """
  Subscribes to the given user's tool state changes.
  """
  def subscribe(user) do
    Phoenix.PubSub.subscribe(@pubsub, topic(user))
  end

  @doc """
  Returns the list of installed tool modules.
  """
  def available do
    Application.get_env(:banter, :tools, [])
  end

  @doc """
  Lists installed tools together with the user's enabled state, as maps:

      %{
        module: module,
        name: binary,
        description: binary,
        enabled: boolean,
        hidden: boolean
      }
  """
  def list(user) do
    states = Map.new(Repo.all(from ToolState, where: [user_id: ^user.id]), &{&1.name, &1.enabled})

    for module <- available() do
      name = module.name()

      %{
        module: module,
        name: name,
        description: module.description(),
        enabled: Map.get(states, name, true),
        hidden: tool_hidden?(module)
      }
    end
  end

  @doc """
  Returns true if the named tool is installed and enabled for the user.
  """
  def enabled?(user, name) do
    with {:ok, _module} <- fetch_tool(name) do
      case Repo.get_by(ToolState, user_id: user.id, name: name) do
        nil -> true
        %ToolState{enabled: enabled} -> enabled
      end
    else
      _ -> false
    end
  end

  @doc """
  Enables or disables an installed tool for the user, broadcasting the
  change.
  """
  def set_enabled(user, name, enabled) when is_boolean(enabled) do
    with {:ok, _module} <- fetch_tool(name) do
      %ToolState{user_id: user.id, name: name}
      |> ToolState.changeset(%{name: name, enabled: enabled})
      |> Repo.insert(
        on_conflict: [
          set: [enabled: enabled, updated_at: DateTime.truncate(DateTime.utc_now(), :second)]
        ],
        conflict_target: [:user_id, :name]
      )
      |> case do
        {:ok, state} ->
          Phoenix.PubSub.broadcast(@pubsub, topic(user), {:tool_toggled, state})
          {:ok, state}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Returns the OpenAI-format tool specs for the user's enabled tools.

  Hidden tools are always included (they are installed and enabled by
  default and cannot be disabled from the UI).
  """
  def enabled_specs(user) do
    for tool <- list(user), tool.enabled or tool.hidden, do: spec_for(tool)
  end

  defp spec_for(tool) do
    %{
      "type" => "function",
      "function" => %{
        "name" => tool.name,
        "description" => tool.description,
        "parameters" => tool.module.parameters()
      }
    }
  end

  @doc """
  Executes the named tool with the given (already JSON-decoded) arguments
  on behalf of the user.

  Returns `{:ok, result}` or `{:error, message}`; the message is suitable
  for sending back to the LLM as the tool result.

  An optional `context` map is forwarded to tools that implement the
  context-aware `execute/2` callback (see `Banter.Tools.Tool`). Tools that
  only implement `execute/1` never see it.
  """
  def execute(user, name, args, context \\ %{}) when is_map(args) and is_map(context) do
    with {:ok, module} <- fetch_tool(name),
         :ok <- ensure_enabled(user, name) do
      try do
        dispatch_execute(module, name, args, context)
      rescue
        exception -> {:error, "tool #{name} crashed: #{Exception.message(exception)}"}
      end
    end
  end

  # Tools may define either `execute/1` (args only) or `execute/2`
  # (args + context). Prefer the context-aware callback when present so
  # tools that need run context (e.g. the active conversation) can use it
  # without breaking tools that do not.
  defp dispatch_execute(module, _name, args, context) do
    if function_exported?(module, :execute, 2) do
      module.execute(args, context)
    else
      module.execute(args)
    end
  end

  defp fetch_tool(name) do
    case Enum.find(available(), fn module -> module.name() == name end) do
      nil -> {:error, "unknown tool: #{name}"}
      module -> {:ok, module}
    end
  end

  defp ensure_enabled(user, name) do
    if enabled?(user, name), do: :ok, else: {:error, "tool #{name} is disabled"}
  end

  defp tool_hidden?(module) do
    function_exported?(module, :hidden?, 0) and module.hidden?()
  end

  defp topic(user), do: "tools:#{user.id}"
end
