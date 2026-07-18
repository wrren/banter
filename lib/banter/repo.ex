defmodule Banter.Repo do
  use Ecto.Repo,
    otp_app: :banter,
    adapter: Ecto.Adapters.Postgres
end
