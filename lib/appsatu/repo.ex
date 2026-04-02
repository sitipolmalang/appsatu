defmodule Appsatu.Repo do
  use Ecto.Repo,
    otp_app: :appsatu,
    adapter: Ecto.Adapters.Postgres
end
