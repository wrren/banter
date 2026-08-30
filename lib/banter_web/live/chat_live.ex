defmodule BanterWeb.ChatLive do
  @moduledoc """
  The main chat interface: a terminal-styled conversation view with a
  sidebar for conversations, tools and model selection.
  """
  use BanterWeb, :live_view

  import BanterWeb.ChatComponents
  alias Phoenix.LiveView.JS

  alias Banter.{Conversations, LLM, Providers, Tools}
  alias Banter.Conversations.{Conversation, Runner}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    socket =
      socket
      |> assign(
        conversation: nil,
        draft: nil,
        draft_stable: "",
        draft_html: "",
        draft_tail: "",
        running: false,
        status: nil,
        tools: visible_tools(user),
        providers: Providers.list_providers(user.id),
        models: LLM.available_models(),
        form: to_form(%{"content" => ""}),
        page_title: "banter"
      )
      |> stream(:conversations, Conversations.list_conversations(user))
      |> stream(:messages, [])

    if connected?(socket), do: Tools.subscribe(user)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case {socket.assigns.live_action, params} do
      {:index, _params} ->
        {:noreply, assign_conversation(socket, nil)}

      {:show, %{"id" => id}} ->
        conversation = Conversations.get_user_conversation!(socket.assigns.current_scope.user, id)
        {:noreply, assign_conversation(socket, conversation)}
    end
  end

  ## Events

  @impl true
  def handle_event("send", %{"content" => content}, socket) do
    conversation = socket.assigns.conversation
    content = String.trim(content)

    cond do
      content == "" ->
        {:noreply, socket}

      is_nil(conversation) or socket.assigns.running ->
        {:noreply, socket}

      true ->
        {:ok, message} =
          Conversations.create_message(conversation, %{role: "user", content: content})

        {:ok, conversation} = Conversations.maybe_retitle(conversation, content)

        case Runner.start(conversation.id) do
          {:ok, _pid} ->
            :ok

          {:error, :already_running} ->
            # another session started a run; we will still receive its events
            :ok
        end

        {:noreply,
         socket
         |> stream_insert(:messages, message)
         |> assign(
           conversation: conversation,
           running: true,
           status: "thinking…",
           form: to_form(%{"content" => ""})
         )
         |> refresh_conversations()}
    end
  end

  def handle_event("new", _params, socket) do
    {:ok, conversation} =
      Conversations.create_conversation(
        socket.assigns.current_scope.user,
        default_conversation_attrs(socket.assigns.providers)
      )

    {:noreply,
     socket
     |> refresh_conversations()
     |> push_patch(to: ~p"/c/#{conversation.id}")}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    conversation = Conversations.get_user_conversation!(socket.assigns.current_scope.user, id)
    {:ok, _} = Conversations.delete_conversation(conversation)

    socket = refresh_conversations(socket)

    if current?(socket, conversation) do
      {:noreply, push_patch(socket, to: ~p"/")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_tool", %{"name" => name}, socket) do
    user = socket.assigns.current_scope.user
    tool = Enum.find(socket.assigns.tools, &(&1.name == name))

    if tool do
      {:ok, _state} = Tools.set_enabled(user, name, not tool.enabled)
    end

    {:noreply, assign(socket, :tools, visible_tools(user))}
  end

  def handle_event("select_model", %{"model" => selection}, socket) do
    with %Conversation{} = conversation <- socket.assigns.conversation,
         {:ok, attrs} <- model_selection_attrs(selection, socket.assigns) do
      {:ok, conversation} = Conversations.update_conversation(conversation, attrs)
      {:noreply, assign(socket, :conversation, conversation)}
    else
      _ -> {:noreply, socket}
    end
  end

  ## Runner and tool events

  @impl true
  def handle_info({:run_started, _id}, socket) do
    {:noreply, socket |> clear_draft() |> assign(running: true, status: "thinking…")}
  end

  def handle_info({:llm_delta, chunk}, socket) do
    draft = (socket.assigns.draft || "") <> chunk
    {stable, tail} = split_draft(draft)

    socket = assign(socket, draft: draft, draft_tail: tail, status: nil)

    socket =
      if stable != socket.assigns.draft_stable do
        assign(socket,
          draft_stable: stable,
          draft_html: BanterWeb.Markdown.to_html(stable)
        )
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:message_appended, message}, socket) do
    socket =
      socket
      |> stream_insert(:messages, message)
      |> refresh_conversations()

    socket =
      if message.role == "assistant" do
        clear_draft(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:tool_call_started, tool_call}, socket) do
    name = get_in(tool_call, ["function", "name"])
    {:noreply, assign(socket, :status, "running #{name}…")}
  end

  def handle_info({:tool_call_finished, _id, _name, _status}, socket) do
    {:noreply, assign(socket, :status, "thinking…")}
  end

  def handle_info({:run_finished, _id}, socket) do
    {:noreply, socket |> clear_draft() |> assign(running: false, status: nil)}
  end

  def handle_info({:compaction_started, _id}, socket) do
    {:noreply, assign(socket, :status, "compacting conversation…")}
  end

  def handle_info({:compaction_finished, _id}, socket) do
    {:noreply, assign(socket, :status, "compaction complete")}
  end

  def handle_info({:run_failed, _id, reason}, socket) do
    {:noreply,
     socket
     |> clear_draft()
     |> assign(running: false, status: nil)
     |> put_flash(:error, "run failed: #{reason}")}
  end

  def handle_info({:tool_toggled, _state}, socket) do
    {:noreply, assign(socket, :tools, visible_tools(socket.assigns.current_scope.user))}
  end

  ## Helpers

  # Tools shown in the sidebar panel: hidden tools are always enabled and
  # never appear in the UI.
  defp visible_tools(user), do: Enum.reject(Tools.list(user), & &1.hidden)

  # Builds the conversation attrs for a model selection. Values prefixed
  # with "db:" reference a stored model (and its provider); anything else
  # is treated as a model id from the global provider config.
  defp model_selection_attrs("db:" <> id, assigns) do
    with {model_id, ""} <- Integer.parse(id),
         {provider, model} <- find_db_model(assigns.providers, model_id),
         true <- not is_nil(model) do
      {:ok,
       %{
         model: model.name,
         provider_id: provider.id,
         llm_model_id: model.id
       }}
    else
      _ -> :error
    end
  end

  defp model_selection_attrs(model, assigns) do
    if model in assigns.models do
      {:ok, %{model: model, provider_id: nil, llm_model_id: nil}}
    else
      :error
    end
  end

  defp find_db_model(providers, model_id) do
    Enum.find_value(providers, {nil, nil}, fn provider ->
      case Enum.find(provider.models, &(&1.id == model_id)) do
        nil -> nil
        model -> {provider, model}
      end
    end)
  end

  defp default_conversation_attrs(providers) do
    case providers do
      [%{models: [model | _]} = provider | _] ->
        %{model: model.name, provider_id: provider.id, llm_model_id: model.id}

      _ ->
        %{model: LLM.default_model()}
    end
  end

  defp assign_conversation(socket, nil) do
    maybe_unsubscribe(socket, socket.assigns.conversation)

    socket
    |> clear_draft()
    |> assign(
      conversation: nil,
      running: false,
      status: nil,
      page_title: "banter"
    )
    |> refresh_conversations()
    |> stream(:messages, [], reset: true)
  end

  defp assign_conversation(socket, %Conversation{} = conversation) do
    maybe_unsubscribe(socket, socket.assigns.conversation)
    if connected?(socket), do: Runner.subscribe(conversation.id)

    socket
    |> clear_draft()
    |> assign(
      conversation: conversation,
      status: nil,
      running: Runner.running?(conversation.id),
      page_title: conversation.title
    )
    |> refresh_conversations()
    |> stream(:messages, Conversations.list_messages(conversation), reset: true)
  end

  # Splits a draft reply into the stable portion (everything up to and
  # including the last newline) and the tail (the incomplete line still
  # being written). Only the stable portion is rendered as markdown, and
  # only when it changes — i.e. once per completed line.
  defp split_draft(draft) do
    case :binary.matches(draft, "\n") do
      [] ->
        {"", draft}

      matches ->
        {pos, 1} = List.last(matches)
        {binary_part(draft, 0, pos + 1), binary_part(draft, pos + 1, byte_size(draft) - pos - 1)}
    end
  end

  defp clear_draft(socket) do
    assign(socket, draft: nil, draft_stable: "", draft_html: "", draft_tail: "")
  end

  defp maybe_unsubscribe(socket, %Conversation{} = conversation) do
    if connected?(socket), do: Runner.unsubscribe(conversation.id)
  end

  defp maybe_unsubscribe(_socket, nil), do: :ok

  defp current?(socket, %Conversation{} = conversation) do
    match?(%Conversation{id: id} when id == conversation.id, socket.assigns.conversation)
  end

  defp refresh_conversations(socket) do
    stream(
      socket,
      :conversations,
      Conversations.list_conversations(socket.assigns.current_scope.user),
      reset: true
    )
  end
end
