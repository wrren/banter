defmodule BanterWeb.LoginLive do
  @moduledoc """
  Username/password sign-in.

  The form posts to `UserSessionController.create/2`, which verifies the
  credentials and starts a session.
  """
  use BanterWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    form = to_form(%{"username" => "", "password" => ""}, as: :user)
    {:ok, assign(socket, form: form, page_title: "sign in · banter")}
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
            <p class="text-sm text-term-dim">sign in to your account</p>
          </div>

          <.form
            for={@form}
            id="login-form"
            action={~p"/users/log-in"}
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
              label="password"
              autocomplete="current-password"
              required
            />
            <.button
              id="login-button"
              variant="primary"
              class="inline-flex w-full items-center justify-center gap-1.5 rounded border px-3 py-1.5 text-sm transition-colors cursor-pointer border-term-green/50 text-term-green hover:bg-term-green/10"
            >
              sign in
            </.button>
          </.form>

          <p class="text-center text-sm text-term-faint">
            no account yet?
            <.link navigate={~p"/users/register"} class="text-term-cyan hover:underline">
              register
            </.link>
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
