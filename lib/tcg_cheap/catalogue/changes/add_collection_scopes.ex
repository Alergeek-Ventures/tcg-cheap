defmodule TcgCheap.Catalogue.Changes.AddCollectionScopes do
  @moduledoc false
  use Ash.Resource.Change

  alias TcgCheap.Catalogue.CardPrinting
  alias TcgCheap.Catalogue.Validations.CollectionScope

  @scopes ["pitch_black_full", "rolling_ir_sir", "curated_playable", "legacy_local"]
  @permanent_scopes ["pitch_black_full", "legacy_local"]

  @impl true
  def change(changeset, _opts, _context),
    do: Ash.Changeset.before_action(changeset, &lock_and_merge/1)

  defp lock_and_merge(changeset) do
    with :ok <- validate_incoming_scopes(Ash.Changeset.get_argument(changeset, :incoming_scopes)),
         :ok <- validate_incoming_expiry(changeset),
         {:ok, latest} <- lock_latest(changeset),
         {:ok, attrs} <- merged_attributes(latest, changeset) do
      changeset =
        Enum.reduce(attrs, changeset, fn {attribute, value}, changeset ->
          Ash.Changeset.force_change_attribute(changeset, attribute, value)
        end)

      case CollectionScope.validate(changeset, [], %{}) do
        :ok ->
          changeset

        {:error, field: field, message: message} ->
          Ash.Changeset.add_error(changeset, field: field, message: message)

        {:error, message} ->
          Ash.Changeset.add_error(changeset, message: message)
      end
    else
      {:error, field: field, message: message} ->
        Ash.Changeset.add_error(changeset, field: field, message: message)

      {:error, message} ->
        Ash.Changeset.add_error(changeset, message: message)
    end
  end

  defp lock_latest(changeset) do
    CardPrinting
    |> Ash.Query.for_read(:lock_for_update_by_id, %{id: Ash.Changeset.get_data(changeset, :id)})
    |> Ash.read_one(domain: TcgCheap.Core, authorize?: false)
    |> case do
      {:ok, %CardPrinting{} = card} -> {:ok, card}
      _ -> {:error, "card printing could not be locked"}
    end
  end

  defp merged_attributes(card, changeset) do
    incoming = Ash.Changeset.get_argument(changeset, :incoming_scopes)
    incoming_expiry = Ash.Changeset.get_argument(changeset, :incoming_expires_on)
    scoped_at = Ash.Changeset.get_argument(changeset, :scoped_at)
    scopes = Enum.uniq(card.collection_scopes ++ incoming) |> Enum.sort()

    source =
      if card.collection_scope_source in ["administrator", "legacy"],
        do: card.collection_scope_source,
        else: "system"

    scoped_at = earliest(card.collection_scoped_at, scoped_at)

    expiry =
      cond do
        Enum.any?(scopes, &(&1 in @permanent_scopes)) -> nil
        source in ["administrator", "legacy"] and is_nil(card.collection_expires_on) -> nil
        true -> max_expiry(card.collection_expires_on, incoming_expiry)
      end

    {:ok,
     collection_scopes: scopes,
     collection_scope_source: source,
     collection_scoped_at: scoped_at,
     collection_expires_on: expiry}
  end

  defp validate_incoming_scopes(scopes) when is_list(scopes) do
    cond do
      scopes == [] ->
        {:error, field: :incoming_scopes, message: "must not be empty"}

      Enum.all?(scopes, &(&1 in @scopes)) ->
        :ok

      true ->
        {:error, field: :incoming_scopes, message: "contains an invalid scope"}
    end
  end

  defp validate_incoming_scopes(_),
    do: {:error, field: :incoming_scopes, message: "must be a list"}

  defp validate_incoming_expiry(changeset) do
    expires_on = Ash.Changeset.get_argument(changeset, :incoming_expires_on)
    scoped_at = Ash.Changeset.get_argument(changeset, :scoped_at)

    if is_nil(expires_on) or Date.compare(expires_on, DateTime.to_date(scoped_at)) != :lt do
      :ok
    else
      {:error, field: :incoming_expires_on, message: "cannot precede scoped_at"}
    end
  end

  defp earliest(nil, incoming), do: incoming

  defp earliest(existing, incoming),
    do: if(DateTime.compare(existing, incoming) == :lt, do: existing, else: incoming)

  defp max_expiry(nil, incoming), do: incoming
  defp max_expiry(existing, nil), do: existing

  defp max_expiry(existing, incoming),
    do: if(Date.compare(existing, incoming) == :gt, do: existing, else: incoming)
end
