defmodule TcgCheap.Catalogue.Changes.LockAndValidateReview do
  @moduledoc "Locks a review row in the action transaction and validates its latest state."
  use Ash.Resource.Change

  alias Ash.Changeset
  alias TcgCheap.Catalogue.Validations.SealedProductApproval
  alias TcgCheap.Catalogue.Validations.SealedProductFields

  @impl true
  def init(opts) do
    valid_resource? = is_atom(opts[:resource])
    valid_lock_action? = is_atom(opts[:lock_action])
    valid_status_attribute? = is_atom(opts[:status_attribute])
    valid_expected? = valid_expected_status?(opts[:expected_status])
    valid_version_argument? = is_nil(opts[:version_argument]) or is_atom(opts[:version_argument])
    valid_mode? = is_nil(opts[:mode]) or opts[:mode] == :product_approval

    if valid_resource? and valid_lock_action? and valid_status_attribute? and valid_expected? and
         valid_version_argument? and valid_mode?,
       do: {:ok, opts},
       else:
         {:error,
          "resource, lock_action, status_attribute, expected_status, version_argument, and mode options are invalid"}
  end

  @impl true
  def change(changeset, opts, _context) do
    Changeset.before_action(changeset, fn changeset -> lock_and_validate(changeset, opts) end)
  end

  defp lock_and_validate(changeset, opts) do
    id = Changeset.get_data(changeset, :id)
    resource = opts[:resource]
    action = opts[:lock_action]

    query =
      resource
      |> Ash.Query.for_read(action, %{id: id})
      |> Ash.Query.lock(:for_update)

    case Ash.read_one(query, domain: TcgCheap.Core, authorize?: false) do
      {:ok, nil} -> Changeset.add_error(changeset, message: "record no longer exists")
      {:ok, latest} -> validate_latest(changeset, latest, opts)
      {:error, error} -> Changeset.add_error(changeset, message: Exception.message(error))
    end
  end

  defp validate_latest(changeset, latest, opts) do
    expected_statuses = List.wrap(opts[:expected_status])

    cond do
      Map.get(latest, opts[:status_attribute]) not in expected_statuses ->
        expected = Enum.join(expected_statuses, " or ")

        Changeset.add_error(changeset,
          message: "may only transition from #{expected}"
        )

      stale_version?(changeset, latest, opts[:version_argument]) ->
        Changeset.add_error(changeset,
          message: "record changed after it was loaded"
        )

      true ->
        validate_completeness(changeset, latest, opts[:mode])
    end
  end

  defp stale_version?(_changeset, _latest, nil), do: false

  defp stale_version?(changeset, latest, version_argument) do
    Changeset.get_argument(changeset, version_argument) != latest.updated_at
  end

  defp valid_expected_status?(status) when is_binary(status), do: true

  defp valid_expected_status?(statuses) when is_list(statuses) do
    statuses != [] and Enum.all?(statuses, &is_binary/1)
  end

  defp valid_expected_status?(_statuses), do: false

  defp validate_completeness(changeset, _latest, nil), do: changeset

  defp validate_completeness(changeset, latest, :product_approval) do
    errors =
      [
        SealedProductApproval.validate_record(latest),
        SealedProductFields.validate_values(
          latest.msrp_pln,
          latest.msrp_source
        )
      ]
      |> Enum.reject(&(&1 == :ok))

    Enum.reduce(errors, changeset, fn {:error, error}, changeset ->
      Changeset.add_error(changeset, error)
    end)
  end
end
