defmodule BanterWeb.ChatLive do
  @moduledoc """
  The main chat interface: a terminal-styled conversation view with a
  sidebar for conversations, tools and model selection.
  """
  use BanterWeb, :live_view

  import BanterWeb.ChatComponents

  alias Banter.{Conversations, LLM, Tools}
  alias Banter.Conversations.{Conversation, Runner}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        conversation: nil,
        draft: nil,
        running: false,
        status: nil,
        tools: Tools.list(),
        models: LLM.available_models(),
        form: to_form(%{"content" => ""}),
        page_title: "banter"
      )
      |> stream(:conversations, Conversations.list_conversations())
      |> stream(:messages, [])

    if connected?(socket), do: Tools.subscribe()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case {socket.assigns.live_action, params} do
      {:index, _params} ->
        {:noreply, assign_conversation(socket, nil)}

      {:show, %{"id" => id}} ->
        conversation = Conversations.get_conversation!(id)
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
    {:ok, conversation} = Conversations.create_conversation(%{model: LLM.default_model()})

    {:noreply,
     socket
     |> refresh_conversations()
     |> push_patch(to: ~p"/c/#{conversation.id}")}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    conversation = Conversations.get_conversation!(id)
    {:ok, _} = Conversations.delete_conversation(conversation)

    socket = refresh_conversations(socket)

    if current?(socket, conversation) do
      {:noreply, push_patch(socket, to: ~p"/")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_tool", %{"name" => name}, socket) do
    tool = Enum.find(socket.assigns.tools, &(&1.name == name))

    if tool do
      {:ok, _state} = Tools.set_enabled(name, not tool.enabled)
    end

    {:noreply, assign(socket, :tools, Tools.list())}
  end

  def handle_event("select_model", %{"model" => model}, socket) do
    with %Conversation{} = conversation <- socket.assigns.conversation,
         true <- model in socket.assigns.models do
      {:ok, conversation} = Conversations.update_conversation(conversation, %{model: model})
      {:noreply, assign(socket, :conversation, conversation)}
    else
      _ -> {:noreply, socket}
    end
  end

  ## Runner and tool events

  @impl true
  def handle_info({:run_started, _id}, socket) do
    {:noreply, assign(socket, running: true, status: "thinking…", draft: nil)}
  end

  def handle_info({:llm_delta, chunk}, socket) do
    {:noreply,
     assign(socket,
       draft: (socket.assigns.draft || "") <> chunk,
       status: nil
     )}
  end

  def handle_info({:message_appended, message}, socket) do
    socket =
      socket
      |> stream_insert(:messages, message)
      |> refresh_conversations()

    socket =
      if message.role == "assistant" do
        assign(socket, draft: nil)
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
    {:noreply, assign(socket, running: false, status: nil, draft: nil)}
  end

  def handle_info({:run_failed, _id, reason}, socket) do
    {:noreply,
     socket
     |> assign(running: false, status: nil, draft: nil)
     |> put_flash(:error, "run failed: #{reason}")}
  end

  def handle_info({:tool_toggled, _state}, socket) do
    {:noreply, assign(socket, :tools, Tools.list())}
  end

  ## Helpers

  defp assign_conversation(socket, nil) do
    maybe_unsubscribe(socket, socket.assigns.conversation)

    socket
    |> assign(
      conversation: nil,
      draft: nil,
      running: false,
      status: nil,
      page_title: "banter"
    )
    |> stream(:messages, [], reset: true)
  end

  defp assign_conversation(socket, %Conversation{} = conversation) do
    maybe_unsubscribe(socket, socket.assigns.conversation)
    if connected?(socket), do: Runner.subscribe(conversation.id)

    socket
    |> assign(
      conversation: conversation,
      draft: nil,
      status: nil,
      running: Runner.running?(conversation.id),
      page_title: conversation.title
    )
    |> stream(:messages, Conversations.list_messages(conversation), reset: true)
  end

  defp maybe_unsubscribe(socket, %Conversation{} = conversation) do
    if connected?(socket), do: Runner.unsubscribe(conversation.id)
  end

  defp maybe_unsubscribe(_socket, nil), do: :ok

  defp current?(socket, %Conversation{} = conversation) do
    match?(%Conversation{id: id} when id == conversation.id, socket.assigns.conversation)
  end

  defp refresh_conversations(socket) do
    stream(socket, :conversations, Conversations.list_conversations(), reset: true)
  end
end
