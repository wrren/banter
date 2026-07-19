defmodule Banter.Providers do
  @moduledoc """
  The Providers context for managing LLM providers and their models.
  """

  import Ecto.Query, warn: false
  alias Banter.Repo
  alias Banter.Crypto
  alias Banter.Providers.Provider
  alias Banter.Providers.Model

  def list_providers(user_id) do
    from(p in Provider, where: p.user_id == ^user_id, preload: [:models])
    |> Repo.all()
  end

  def get_provider!(id), do: Repo.get!(Provider, id) |> Repo.preload(:models)

  def get_provider(id), do: Repo.get(Provider, id) |> Repo.preload(:models)

  def get_user_provider!(user_id, name) do
    from(p in Provider, where: p.user_id == ^user_id and p.name == ^name, preload: [:models])
    |> Repo.one!()
  end

  def create_provider(user_id, attrs) do
    api_key = Map.get(attrs, "api_key") || Map.get(attrs, :api_key) || ""

    encrypted_key = Crypto.encrypt(api_key)

    attrs_for_changelog =
      attrs
      |> Map.delete("api_key")
      |> Map.delete(:api_key)
      |> Map.put("encrypted_api_key", encrypted_key)
      |> Map.put("user_id", user_id)

    %Provider{}
    |> Provider.changeset(attrs_for_changelog)
    |> Repo.insert()
  end

  def update_provider(%Provider{} = provider, attrs) do
    api_key = Map.get(attrs, "api_key") || Map.get(attrs, :api_key)

    attrs =
      if api_key && api_key != "" do
        attrs
        |> Map.delete("api_key")
        |> Map.delete(:api_key)
        |> Map.put("encrypted_api_key", Crypto.encrypt(api_key))
      else
        attrs
        |> Map.delete("api_key")
        |> Map.delete(:api_key)
      end

    provider
    |> Provider.changeset(attrs)
    |> Repo.update()
  end

  def delete_provider(%Provider{} = provider) do
    Repo.delete(provider)
  end

  def decrypt_api_key(%Provider{} = provider) do
    Crypto.decrypt(provider.encrypted_api_key)
  end

  def get_model!(id), do: Repo.get!(Model, id)

  def get_model(id), do: Repo.get(Model, id)

  def create_model(provider_id, attrs) do
    attrs = Map.put(attrs, "provider_id", provider_id)

    %Model{}
    |> Model.changeset(attrs)
    |> Repo.insert()
  end

  def update_model(%Model{} = model, attrs) do
    model
    |> Model.changeset(attrs)
    |> Repo.update()
  end

  def delete_model(%Model{} = model) do
    Repo.delete(model)
  end

  def list_models(provider_id) do
    from(m in Model, where: m.provider_id == ^provider_id)
    |> Repo.all()
  end
end
