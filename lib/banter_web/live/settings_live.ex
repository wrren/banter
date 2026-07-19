defmodule BanterWeb.SettingsLive do
  @moduledoc """
  Account settings: change password, manage providers and models.

  Changing the password invalidates all sessions, so on success the user
  is redirected to the login page to sign back in with the new password.
  """
  use BanterWeb, :live_view

  alias Banter.{Accounts, Providers}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    providers = Providers.list_providers(user.id)

    {:ok,
     assign(socket,
       form: to_form(Accounts.change_user_password(user)),
       providers: providers,
       provider_form: to_form(%{}, as: :provider),
       model_forms: %{},
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
        {:noreply,
         socket
         |> put_flash(:info, "Password updated. Please sign in with your new password.")
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("validate_provider", %{"provider" => params}, socket) do
    {:noreply, assign(socket, provider_form: to_form(params, as: :provider))}
  end

  def handle_event("add_provider", %{"provider" => params}, socket) do
    user = socket.assigns.current_scope.user

    case Providers.create_provider(user.id, params) do
      {:ok, _provider} ->
        providers = Providers.list_providers(user.id)

        {:noreply,
         socket
         |> assign(providers: providers, provider_form: to_form(%{}, as: :provider))
         |> put_flash(:info, "Provider added.")}

      {:error, changeset} ->
        {:noreply, assign(socket, provider_form: to_form(changeset, as: :provider))}
    end
  end

  def handle_event("delete_provider", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user

    case Integer.parse(id) do
      {provider_id, _} ->
        provider = Providers.get_provider(provider_id)

        if provider && provider.user_id == user.id do
          {:ok, _} = Providers.delete_provider(provider)
          providers = Providers.list_providers(user.id)
          {:noreply, assign(socket, providers: providers)}
        else
          {:noreply, socket}
        end

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("validate_model", %{"provider_id" => provider_id, "model" => params}, socket) do
    model_forms =
      Map.put(
        socket.assigns.model_forms,
        String.to_integer(provider_id),
        to_form(params, as: :model)
      )

    {:noreply, assign(socket, model_forms: model_forms)}
  end

  def handle_event("add_model", %{"provider_id" => provider_id, "model" => params}, socket) do
    user = socket.assigns.current_scope.user

    case Integer.parse(provider_id) do
      {provider_id_val, _} ->
        provider = Providers.get_provider(provider_id_val)

        if provider && provider.user_id == user.id do
          case Providers.create_model(provider.id, params) do
            {:ok, _model} ->
              providers = Providers.list_providers(user.id)
              model_forms = Map.delete(socket.assigns.model_forms, provider_id_val)
              {:noreply, assign(socket, providers: providers, model_forms: model_forms)}

            {:error, changeset} ->
              model_forms =
                Map.put(
                  socket.assigns.model_forms,
                  provider_id_val,
                  to_form(changeset, as: :model)
                )

              {:noreply, assign(socket, model_forms: model_forms)}
          end
        else
          {:noreply, socket}
        end

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event(
        "delete_model",
        %{"provider_id" => provider_id, "model_id" => model_id},
        socket
      ) do
    user = socket.assigns.current_scope.user

    case {Integer.parse(provider_id), Integer.parse(model_id)} do
      {{provider_id_val, _}, {model_id_val, _}} ->
        provider = Providers.get_provider(provider_id_val)

        if provider && provider.user_id == user.id do
          model = Providers.get_model(model_id_val)

          if model && model.provider_id == provider_id_val do
            {:ok, _} = Providers.delete_model(model)
            providers = Providers.list_providers(user.id)
            {:noreply, assign(socket, providers: providers)}
          else
            {:noreply, socket}
          end
        else
          {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex h-full">
        <%!-- Sidebar --%>
        <aside class="flex w-64 shrink-0 flex-col border-r border-term-border bg-term-panel">
          <div class="border-b border-term-border px-3 py-3">
            <.link navigate={~p"/"} class="text-term-green font-bold tracking-tight">
              banter<span class="banter-cursor">▊</span>
            </.link>
          </div>

          <nav class="flex-1 overflow-y-auto py-2">
            <p class="px-3 pb-1 text-xs uppercase tracking-wider text-term-faint">settings</p>
            <a
              href="#account"
              class="block px-3 py-1.5 text-sm text-term-dim transition-colors hover:text-term-fg"
            >
              account
            </a>
            <a
              href="#providers"
              class="block px-3 py-1.5 text-sm text-term-dim transition-colors hover:text-term-fg"
            >
              providers
            </a>
          </nav>

          <div class="space-y-2 border-t border-term-border px-3 py-3">
            <.link
              id="back-to-chat"
              navigate={~p"/"}
              class="flex items-center gap-1.5 rounded border border-term-border px-2.5 py-1.5 text-sm text-term-cyan transition-colors hover:border-term-cyan/50 hover:bg-term-cyan/10"
            >
              <.icon name="hero-arrow-left" class="size-3.5" /> back to chat
            </.link>
            <div class="flex items-center justify-between">
              <span
                class="truncate text-sm text-term-dim"
                title={"signed in as #{@current_scope.user.username}"}
              >
                <span class="text-term-faint">@</span>{@current_scope.user.username}
              </span>
              <.link
                id="logout-link"
                href={~p"/users/log-out"}
                method="delete"
                title="Log out"
                class="text-term-faint transition-colors hover:text-term-red"
              >
                <.icon name="hero-arrow-right-on-rectangle" class="size-4" />
              </.link>
            </div>
          </div>
        </aside>

        <%!-- Main panel --%>
        <div class="flex min-w-0 flex-1 flex-col">
          <header class="flex items-center gap-3 border-b border-term-border px-6 py-3">
            <h1 class="min-w-0 flex-1 truncate text-sm text-term-fg font-medium">settings</h1>
          </header>

          <div class="flex-1 overflow-y-auto">
            <div class="mx-auto max-w-2xl space-y-8 px-6 py-6">
              <%!-- Account --%>
              <section id="account" class="scroll-mt-6 space-y-3">
                <div>
                  <h2 class="text-sm text-term-green font-medium">account</h2>
                  <p class="text-xs text-term-faint">
                    change your password — you will be signed out afterwards
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
              </section>

              <%!-- Providers --%>
              <section id="providers" class="scroll-mt-6 space-y-3">
                <div>
                  <h2 class="text-sm text-term-green font-medium">providers</h2>
                  <p class="text-xs text-term-faint">
                    LLM providers and their models — select them per conversation in the chat sidebar
                  </p>
                </div>

                <div
                  :if={@providers == []}
                  class="rounded border border-dashed border-term-border px-4 py-6 text-center"
                >
                  <p class="text-sm text-term-dim">no providers yet</p>
                  <p class="mt-1 text-xs text-term-faint">
                    add one below to manage models and per-model context limits
                  </p>
                </div>

                <div
                  :for={provider <- @providers}
                  id={"provider-#{provider.id}"}
                  class="overflow-hidden rounded border border-term-border bg-term-panel"
                >
                  <div class="flex items-center gap-3 border-b border-term-border px-4 py-2.5">
                    <div class="min-w-0 flex-1">
                      <p class="truncate text-sm text-term-fg font-medium">{provider.name}</p>
                      <p class="truncate text-xs text-term-faint">{provider.base_url}</p>
                    </div>
                    <span class="shrink-0 rounded border border-term-border px-1.5 py-0.5 text-[10px] uppercase tracking-wider text-term-faint">
                      {provider.type}
                    </span>
                    <button
                      id={"delete-provider-#{provider.id}"}
                      phx-click="delete_provider"
                      phx-value-id={provider.id}
                      data-confirm={"Delete provider #{provider.name} and all its models?"}
                      title="Delete provider"
                      class="shrink-0 text-term-faint transition-colors hover:text-term-red cursor-pointer"
                    >
                      <.icon name="hero-trash" class="size-4" />
                    </button>
                  </div>

                  <div class="space-y-2 px-4 py-3">
                    <div
                      :if={provider.models == []}
                      class="rounded border border-dashed border-term-border px-3 py-3 text-center text-xs text-term-faint"
                    >
                      no models yet — add one below
                    </div>

                    <div
                      :for={model <- provider.models}
                      id={"model-#{model.id}"}
                      class="group flex items-center gap-3 rounded border border-term-border/50 bg-term-bg px-3 py-2"
                    >
                      <div class="min-w-0 flex-1">
                        <p class="truncate text-sm text-term-fg">{model.name}</p>
                        <p class="text-xs text-term-faint">
                          {format_context_limit(model.context_limit)} ctx
                          <span :if={model.compaction_threshold}>
                            · compacts at {format_threshold(model.compaction_threshold)}
                          </span>
                          <span :if={!model.supports_tools}>· no tools</span>
                        </p>
                      </div>
                      <button
                        id={"delete-model-#{model.id}"}
                        phx-click="delete_model"
                        phx-value-provider_id={provider.id}
                        phx-value-model_id={model.id}
                        data-confirm={"Delete model #{model.name}?"}
                        title="Delete model"
                        class="shrink-0 text-term-faint opacity-0 transition-opacity group-hover:opacity-100 hover:text-term-red cursor-pointer"
                      >
                        <.icon name="hero-x-mark" class="size-3.5" />
                      </button>
                    </div>

                    <.form
                      :let={f}
                      as={:model}
                      for={Map.get(@model_forms, provider.id, to_form(%{}))}
                      id={"model-form-#{provider.id}"}
                      phx-change="validate_model"
                      phx-value-provider_id={provider.id}
                      phx-submit="add_model"
                      class="space-y-2 pt-1"
                    >
                      <div class="grid grid-cols-[1fr_7rem_6rem] items-end gap-2">
                        <.input
                          field={f[:name]}
                          type="text"
                          label="model name"
                          placeholder="e.g., openai/gpt-4o-mini"
                          required
                        />
                        <.input
                          field={f[:context_limit]}
                          type="number"
                          label="context limit"
                          placeholder="128000"
                          required
                        />
                        <.input
                          field={f[:compaction_threshold]}
                          type="number"
                          label="threshold"
                          placeholder="0.8"
                          step="0.05"
                          min="0.1"
                          max="1"
                        />
                      </div>
                      <.button
                        id={"add-model-#{provider.id}"}
                        variant="primary"
                        class="inline-flex items-center gap-1.5 rounded border px-2.5 py-1 text-xs transition-colors cursor-pointer border-term-green/50 text-term-green hover:bg-term-green/10"
                      >
                        <.icon name="hero-plus" class="size-3" /> add model
                      </.button>
                    </.form>
                  </div>
                </div>

                <%!-- Add provider --%>
                <div class="rounded border border-term-border bg-term-panel p-4">
                  <h3 class="mb-3 text-sm text-term-fg font-medium">add provider</h3>
                  <.form
                    for={@provider_form}
                    id="provider-form"
                    phx-change="validate_provider"
                    phx-submit="add_provider"
                    class="space-y-3"
                  >
                    <div class="grid grid-cols-2 gap-3">
                      <.input
                        field={@provider_form[:name]}
                        type="text"
                        label="name"
                        placeholder="e.g., OpenRouter"
                        required
                      />
                      <.input
                        field={@provider_form[:type]}
                        type="select"
                        label="type"
                        options={[{"OpenAI compatible", "openai_compatible"}]}
                        required
                      />
                    </div>
                    <.input
                      field={@provider_form[:base_url]}
                      type="text"
                      label="base URL"
                      placeholder="https://openrouter.ai/api/v1"
                      required
                    />
                    <.input
                      field={@provider_form[:api_key]}
                      type="password"
                      label="API key"
                      placeholder="sk-..."
                      autocomplete="off"
                      required
                    />
                    <.button
                      id="add-provider-button"
                      variant="primary"
                      class="inline-flex items-center gap-1.5 rounded border px-3 py-1.5 text-sm transition-colors cursor-pointer border-term-green/50 text-term-green hover:bg-term-green/10"
                    >
                      <.icon name="hero-plus" class="size-3.5" /> add provider
                    </.button>
                  </.form>
                </div>
              </section>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp format_context_limit(limit) when is_integer(limit) do
    cond do
      limit >= 1_000_000 -> "#{Float.round(limit / 1_000_000, 1)}M"
      limit >= 1_000 -> "#{div(limit, 1_000)}k"
      true -> to_string(limit)
    end
  end

  defp format_context_limit(_), do: "?"

  defp format_threshold(%Decimal{} = threshold) do
    threshold
    |> Decimal.mult(100)
    |> Decimal.round(0)
    |> Decimal.to_string()
    |> Kernel.<>("%")
  end

  defp format_threshold(_), do: "80%"
end
