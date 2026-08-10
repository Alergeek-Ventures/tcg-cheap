defmodule TcgCheap.Catalogue.Changes.LockAndValidateCardPrintingMapping do
  @moduledoc "Locks a CardPrinting and validates an administrator mapping transition."
  use Ash.Resource.Change

  alias TcgCheap.Accounts.AdminActor

  @valid_statuses ["pending", "matched", "unmatched", "review"]

  @impl true
  def init(opts) when is_list(opts) do
    allowed = Keyword.get(opts, :allowed_statuses, @valid_statuses)
    no_op? = Keyword.get(opts, :reject_no_op?, false)

    if Keyword.keyword?(opts) and is_list(allowed) and allowed != [] and
         Enum.all?(allowed, &(&1 in @valid_statuses)) and is_boolean(no_op?) do
      {:ok, opts}
    else
      {:error, "invalid CardPrinting mapping lock options"}
    end
  end

  def init(_), do: {:error, "CardPrinting mapping lock options must be a keyword list"}

  @impl true
  def change(changeset, opts, context) do
    allowed = Keyword.get(opts, :allowed_statuses, ["pending", "matched", "unmatched", "review"])
    reject_no_op? = Keyword.get(opts, :reject_no_op?, false)

    Ash.Changeset.before_action(
      changeset,
      &lock_and_validate(&1, context.actor, allowed, reject_no_op?)
    )
  end

  defp lock_and_validate(changeset, actor, allowed, reject_no_op?) do
    with :ok <- AdminActor.validate(actor),
         :ok <- validate_reason(Ash.Changeset.get_argument(changeset, :reason)) do
      validate_locked_mapping(changeset, allowed, reject_no_op?)
    else
      _error ->
        Ash.Changeset.add_error(changeset,
          message: "administrator actor and nonblank reason are required"
        )
    end
  end

  defp validate_locked_mapping(changeset, allowed, reject_no_op?) do
    id = Ash.Changeset.get_data(changeset, :id)

    query =
      TcgCheap.Catalogue.CardPrinting
      |> Ash.Query.for_read(:lock_for_update_by_id, %{id: id})

    case Ash.read_one(query, domain: TcgCheap.Core, authorize?: false) do
      {:ok, latest} ->
        validate_latest(changeset, latest, allowed, reject_no_op?)

      {:error, _error} ->
        Ash.Changeset.add_error(changeset, message: "mapping could not be locked")
    end
  end

  defp validate_latest(changeset, latest, allowed, reject_no_op?) do
    expected = Ash.Changeset.get_argument(changeset, :expected_updated_at)

    cond do
      latest.mapping_status not in allowed ->
        Ash.Changeset.add_error(changeset, message: "mapping is not in a transition state")

      latest.updated_at != expected or Ash.Changeset.get_data(changeset, :updated_at) != expected ->
        Ash.Changeset.add_error(changeset, message: "mapping changed after it was loaded")

      no_op?(changeset, latest, reject_no_op?) ->
        Ash.Changeset.add_error(changeset, message: "mapping correction is a no-op")

      true ->
        changeset
    end
  end

  defp no_op?(_changeset, _latest, false), do: false

  defp no_op?(changeset, latest, true) do
    latest.mapping_status == "matched" and latest.mapping_authority == "administrator" and
      latest.cardmarket_product_id ==
        Ash.Changeset.get_argument(changeset, :cardmarket_product_id)
  end

  defp validate_reason(reason) when is_binary(reason) do
    if String.trim(reason) != "", do: :ok, else: {:error, :blank_reason}
  end

  defp validate_reason(_), do: {:error, :invalid_reason}
end
