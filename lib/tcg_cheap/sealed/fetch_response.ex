defmodule TcgCheap.Sealed.FetchResponse do
  @moduledoc """
  One response a shop fetch has already read, kept so the fetch can go on
  after a restart instead of reading the shop again
  (`TcgCheap.Sealed.FetchJournal`). Rows belong to one fetch job (`run_id`, its
  Oban job id) and are deleted when it finishes; they are working state, not
  data the site shows.

  `request` names the request (its place in the fetch and its path and query),
  `body` is the compressed response.
  """

  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Sealed,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "sealed_fetch_responses"
    repo TcgCheap.Repo

    custom_indexes do
      index [:shop]
      index [:inserted_at]
    end
  end

  actions do
    defaults [:read]

    read :for_run do
      argument :run_id, :integer, allow_nil?: false
      filter expr(run_id == ^arg(:run_id))
    end

    create :record do
      accept [:run_id, :shop, :request, :body]
      upsert? true
      upsert_fields [:body]
    end

    read :left_over do
      description "Responses of other runs of the shop, and of any run stored before the given time."

      argument :shop, :string, allow_nil?: false
      argument :run_id, :integer, allow_nil?: false
      argument :before, :utc_datetime_usec, allow_nil?: false

      filter expr(
               inserted_at < ^arg(:before) or
                 (shop == ^arg(:shop) and run_id != ^arg(:run_id))
             )
    end

    destroy :discard
  end

  attributes do
    attribute :run_id, :integer, primary_key?: true, allow_nil?: false
    attribute :request, :string, primary_key?: true, allow_nil?: false

    attribute :shop, :string, allow_nil?: false, constraints: [max_length: 40]
    attribute :body, :binary, allow_nil?: false
    create_timestamp :inserted_at
  end
end
