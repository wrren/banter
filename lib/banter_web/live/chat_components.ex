defmodule BanterWeb.ChatComponents do
  @moduledoc """
  Components for rendering chat conversations in Banter's terminal style.
  """
  use BanterWeb, :html

  alias Phoenix.LiveView.JS

  @tool_result_preview 400

  @doc """
  Renders a single conversation message based on its role.
  """
  attr :id, :string, required: true
  attr :message, :map, required: true

  def chat_message(assigns) do
    ~H"""
    <div id={@id} class="px-4 py-2">
      <%= case @message.role do %>
        <% "user" -> %>
          <.user_message message={@message} />
        <% "assistant" -> %>
          <.assistant_message message={@message} />
        <% "tool" -> %>
          <.tool_result id={"#{@id}-result"} message={@message} />
      <% end %>
    </div>
    """
  end

  defp user_message(assigns) do
    ~H"""
    <div class="flex gap-2">
      <span class="text-term-green select-none font-bold">❯</span>
      <div class="min-w-0 whitespace-pre-wrap break-words text-term-fg">{@message.content}</div>
    </div>
    """
  end

  defp assistant_message(assigns) do
    ~H"""
    <div class="space-y-1">
      <div :if={@message.content not in [nil, ""]} class="markdown min-w-0">
        {raw(BanterWeb.Markdown.to_html(@message.content))}
      </div>
      <.tool_call_line :for={tool_call <- @message.tool_calls || []} tool_call={tool_call} />
    </div>
    """
  end

  defp tool_call_line(assigns) do
    ~H"""
    <div class="text-sm">
      <span class="text-term-amber select-none">$</span>
      <span class="text-term-cyan">{tool_name(@tool_call)}</span>
      <span class="text-term-faint">{tool_args(@tool_call)}</span>
    </div>
    """
  end

  defp tool_result(assigns) do
    {preview, rest} = split_content(assigns.message.content, @tool_result_preview)

    assigns =
      assigns
      |> assign(:preview, preview)
      |> assign(:rest, rest)
      |> assign(:rest_length, if(rest, do: String.length(rest), else: 0))

    ~H"""
    <div id={@id} class="group/result text-sm text-term-dim">
      <span class="text-term-faint select-none">⎿ </span><span class="whitespace-pre-wrap break-words">{@preview}</span>
      <%= if @rest do %>
        <span class="hidden group-[.expanded]/result:inline whitespace-pre-wrap break-words">{@rest}</span>
        <button
          type="button"
          id={"#{@id}-toggle"}
          phx-click={JS.toggle_class("expanded", to: "##{@id}")}
          class="ml-1 cursor-pointer underline decoration-dotted text-term-faint hover:text-term-cyan"
        >
          <span class="group-[.expanded]/result:hidden">… {@rest_length} more</span>
          <span class="hidden group-[.expanded]/result:inline">show less</span>
        </button>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders the in-progress assistant reply with a blinking block cursor.

  Deliberately plain text: the reply is re-rendered as markdown (by
  `chat_message/1`) once the run completes, which avoids re-rendering
  markdown on every streamed token.
  """
  attr :draft, :string, required: true

  def assistant_draft(assigns) do
    ~H"""
    <div id="assistant-draft" class="px-4 py-2">
      <span class="whitespace-pre-wrap break-words text-term-fg">{@draft}</span>
      <span class="banter-cursor text-term-green select-none">▊</span>
    </div>
    """
  end

  @doc """
  Renders the status line shown while a run is in progress.
  """
  attr :status, :string, required: true

  def run_status(assigns) do
    ~H"""
    <div id="run-status" class="flex items-center gap-2 px-4 py-1 text-sm text-term-dim">
      <.icon name="hero-arrow-path" class="size-3.5 animate-spin text-term-violet" />
      <span>{@status}</span>
    </div>
    """
  end

  @doc false
  def tool_name(tool_call), do: get_in(tool_call, ["function", "name"]) || "unknown_tool"

  @doc false
  def tool_args(tool_call) do
    args = get_in(tool_call, ["function", "arguments"]) || ""

    if String.length(args) > 120 do
      String.slice(args, 0, 120) <> "…"
    else
      args
    end
  end

  defp split_content(nil, _max), do: {"", nil}

  defp split_content(content, max) do
    if String.length(content) > max do
      {String.slice(content, 0, max), String.slice(content, max..-1//1)}
    else
      {content, nil}
    end
  end
end
