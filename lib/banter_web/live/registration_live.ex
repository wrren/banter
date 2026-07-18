defmodule BanterWeb.RegistrationLive do
  @moduledoc """
  Account registration with username and password.

  The form validates inline via `phx-change` and posts to
  `UserSessionController.register/2`, which creates the account and
  starts a session.
  """
  use BanterWeb, :live_view

  alias Banter.Accounts
  alias Banter.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_registration(%User{})

    {:ok, assign(socket, form: to_form(changeset), page_title: "register · banter")}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      %User{}
      |> Accounts.change_user_registration(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex h-full items-center justify-center px-4">
        <div class="w-full max-w-sm space-y-4">
          <div class="text-center">
            <p class="text-lg text-term-green font-bold">
              banter<span class="banter-cursor">▊</span>
            </p>
            <p class="text-sm text-term-dim">create an account</p>
          </div>

          <.form
            for={@form}
            id="registration-form"
            action={~p"/users/register"}
            phx-change="validate"
            class="space-y-3 rounded border border-term-border bg-term-panel p-4"
          >
            <.input
              field={@form[:username]}
              type="text"
              label="username"
              autocomplete="username"
              required
            />
            <.input
              field={@form[:password]}
              type="password"
              label="password (12+ characters)"
              autocomplete="new-password"
              required
            />
            <.button
              id="register-button"
              variant="primary"
              class="inline-flex w-full items-center justify-center gap-1.5 rounded border px-3 py-1.5 text-sm transition-colors cursor-pointer border-term-green/50 text-term-green hover:bg-term-green/10"
            >
              register
            </.button>
          </.form>

          <p class="text-center text-sm text-term-faint">
            already have an account?
            <.link navigate={~p"/users/log-in"} class="text-term-cyan hover:underline">
              sign in
            </.link>
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
