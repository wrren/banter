defmodule BanterWeb.SettingsLive do
  @moduledoc """
  Account settings: change password.

  Changing the password invalidates all sessions, so on success the user
  is redirected to the login page to sign back in with the new password.
  """
  use BanterWeb, :live_view

  alias Banter.Accounts

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     assign(socket,
       form: to_form(Accounts.change_user_password(user)),
       page_title: "settings · banter"
     )}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("change_password", %{"user" => params}, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.update_user_password(user, params["current_password"], params) do
      {:ok, _user} ->
        # all sessions were invalidated; sign in again with the new password
        {:noreply,
         socket
         |> put_flash(:info, "Password updated. Please sign in with your new password.")
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex h-full items-center justify-center px-4">
        <div class="w-full max-w-sm space-y-4">
          <div class="text-center">
            <p class="text-lg text-term-green font-bold">settings</p>
            <p class="text-sm text-term-dim">
              signed in as <span class="text-term-fg">{@current_scope.user.username}</span>
            </p>
          </div>

          <.form
            for={@form}
            id="password-form"
            phx-change="validate"
            phx-submit="change_password"
            class="space-y-3 rounded border border-term-border bg-term-panel p-4"
          >
            <.input
              field={@form[:current_password]}
              type="password"
              label="current password"
              autocomplete="current-password"
              required
            />
            <.input
              field={@form[:password]}
              type="password"
              label="new password (12+ characters)"
              autocomplete="new-password"
              required
            />
            <.input
              field={@form[:password_confirmation]}
              type="password"
              label="confirm new password"
              autocomplete="new-password"
              required
            />
            <.button
              id="change-password-button"
              variant="primary"
              class="inline-flex w-full items-center justify-center gap-1.5 rounded border px-3 py-1.5 text-sm transition-colors cursor-pointer border-term-green/50 text-term-green hover:bg-term-green/10"
            >
              change password
            </.button>
          </.form>

          <p class="text-center text-sm text-term-faint">
            <.link navigate={~p"/"} class="text-term-cyan hover:underline">
              ← back to conversations
            </.link>
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
