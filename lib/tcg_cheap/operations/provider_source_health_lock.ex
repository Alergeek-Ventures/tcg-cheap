defmodule TcgCheap.Operations.ProviderSourceHealthLock do
  @moduledoc "Shared transaction lock for provider status and source-health changes."

  def lock_source!(provider_key) when is_binary(provider_key) do
    TcgCheap.Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [key(provider_key)])
  end

  def lock_provider!(provider_key) when is_binary(provider_key) do
    TcgCheap.Repo.query!(
      "SELECT id, status FROM acquisition_data_providers WHERE provider_key = $1 FOR UPDATE",
      [provider_key]
    )
  end

  defp key(provider_key), do: "tcg_cheap:source_health:" <> provider_key
end
