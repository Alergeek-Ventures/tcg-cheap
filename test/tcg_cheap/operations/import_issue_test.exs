defmodule TcgCheap.Operations.ImportIssueTest do
  use TcgCheap.DataCase, async: false

  alias TcgCheap.Accounts.Admin
  alias TcgCheap.Operations
  alias TcgCheap.Operations.ImportIssues

  setup do
    {:ok, %{rows: [[admin_id]]}} =
      TcgCheap.Repo.query(
        "INSERT INTO admins (id, email, hashed_password) VALUES (gen_random_uuid(), $1, 'test') RETURNING id",
        ["import-issue-#{System.unique_integer([:positive])}@example.test"]
      )

    TcgCheap.Repo.delete_all("import_issues")
    %{actor: %Admin{id: admin_id}}
  end

  test "retained reads require an administrator", %{actor: actor} do
    assert {:ok, []} = Operations.list_admin_import_issues(actor: actor)
    assert {:error, _} = Operations.list_admin_import_issues(actor: %{}, authorize?: true)
  end

  test "normalizes malformed and opaque reasons without retaining secrets" do
    now = ~U[2026-01-01 00:00:00.123456Z]
    provider = "tcgdex_catalogue"

    assert :ok =
             ImportIssues.record(
               provider,
               "card_catalogue_sync",
               "set_validation",
               "set",
               "set-1",
               {:malformed_response, {:bearer_secret, "payload"}},
               now
             )

    assert :ok =
             ImportIssues.record(
               provider,
               "card_catalogue_sync",
               "set_fetch",
               "set",
               "set-2",
               {:provider_error, "private-url?token=secret"},
               now
             )

    {:ok, issues} = Operations.list_admin_import_issues(authorize?: false)

    assert Enum.any?(
             issues,
             &(&1.issue_kind == "malformed" and &1.issue_code == "malformed_response")
           )

    assert Enum.any?(issues, &(&1.issue_kind == "failed" and &1.issue_code == "unknown"))
    refute inspect(issues) =~ "bearer_secret"
    refute inspect(issues) =~ "private-url"
  end

  test "exact identity is monotonic and preserves first_seen_at", %{actor: actor} do
    provider = "tcgdex_catalogue"
    first = ~U[2026-01-01 00:00:01.000000Z]
    newer = ~U[2026-01-01 00:00:02.000000Z]
    older = ~U[2025-12-31 00:00:00.000000Z]
    args = [provider, "card_catalogue_sync", "set_fetch", "set", "set-1", "failed", "timeout"]

    record = fn timestamp ->
      apply(Operations, :record_import_issue, args ++ [timestamp, [authorize?: false]])
    end

    assert {:ok, initial} = record.(first)
    assert {:ok, _same} = record.(older)
    assert {:ok, updated} = record.(newer)
    assert updated.id == initial.id
    assert updated.first_seen_at == first
    assert updated.last_seen_at == newer
    assert {:ok, [listed]} = Operations.list_admin_import_issues(actor: actor)
    assert listed.id == initial.id
  end

  test "records sealed retailer evidence for every refresh stage", %{actor: actor} do
    provider = "sealed_retailer:shop_1"
    retailer_id = "aabbccdd-eeff-0011-2233-445566778899"
    now = ~U[2026-01-01 00:00:00.123456Z]

    for stage <- ["retailer_fetch", "listing_validation", "listing_import"] do
      assert :ok =
               ImportIssues.record(
                 provider,
                 "sealed_retailer_refresh",
                 stage,
                 "retailer",
                 retailer_id,
                 :malformed_listing,
                 now
               )
    end

    assert {:ok, issues} = Operations.list_admin_import_issues(actor: actor)
    assert length(issues) == 3

    assert Enum.all?(
             issues,
             &(&1.provider_key == provider and &1.target_key == retailer_id and
                 &1.issue_kind == "malformed" and &1.issue_code == "malformed_response")
           )
  end

  test "rejects sealed cross-provider, matrix, unsafe provider, and UUID values" do
    timestamp = DateTime.utc_now()

    valid = [
      "sealed_retailer:shop",
      "sealed_retailer_refresh",
      "retailer_fetch",
      "retailer",
      Ecto.UUID.generate(),
      "failed",
      "transport"
    ]

    for args <- [
          [
            "tcgdex_catalogue",
            "sealed_retailer_refresh",
            "retailer_fetch",
            "retailer",
            Ecto.UUID.generate(),
            "failed",
            "transport"
          ],
          [
            "sealed_retailer:shop",
            "sealed_retailer_refresh",
            "set_fetch",
            "set",
            "set-1",
            "failed",
            "transport"
          ],
          [
            "sealed_retailer:shop?secret",
            "sealed_retailer_refresh",
            "retailer_fetch",
            "retailer",
            Ecto.UUID.generate(),
            "failed",
            "transport"
          ],
          [
            "sealed_retailer:shop",
            "sealed_retailer_refresh",
            "retailer_fetch",
            "retailer",
            String.upcase(Ecto.UUID.generate()),
            "failed",
            "transport"
          ],
          [
            "sealed_retailer:shop",
            "sealed_retailer_refresh",
            "retailer_fetch",
            "retailer",
            "not-a-uuid",
            "failed",
            "transport"
          ]
        ] do
      assert {:error, _} =
               apply(Operations, :record_import_issue, args ++ [timestamp, [authorize?: false]])
    end

    for {provider, target} <- [
          {"sealed_retailer:shop\n", Ecto.UUID.generate()},
          {"sealed_retailer:shop", Ecto.UUID.generate() <> "\n"}
        ] do
      assert {:error, :import_issue_persistence_failed} =
               ImportIssues.record(
                 provider,
                 "sealed_retailer_refresh",
                 "retailer_fetch",
                 "retailer",
                 target,
                 :transport_error,
                 timestamp
               )
    end

    assert :ok =
             ImportIssues.record(
               Enum.at(valid, 0),
               Enum.at(valid, 1),
               Enum.at(valid, 2),
               Enum.at(valid, 3),
               Enum.at(valid, 4),
               {:malformed_listing, "secret-url"},
               timestamp
             )

    {:ok, [issue]} = Operations.list_admin_import_issues(authorize?: false)
    refute inspect(issue) =~ "secret-url"
  end

  test "normalizes sealed HTTP status maps without retaining response details", %{actor: actor} do
    provider = "sealed_retailer:shop"
    retailer_id = Ecto.UUID.generate()
    now = ~U[2026-01-01 00:00:00.000000Z]

    for {status, expected_code} <- [{408, "timeout"}, {429, "rate_limit"}] do
      assert :ok =
               ImportIssues.record(
                 provider,
                 "sealed_retailer_refresh",
                 "retailer_fetch",
                 "retailer",
                 retailer_id,
                 {:http_error, %{status: status, response: "secret-#{status}"}},
                 DateTime.add(now, status, :second)
               )

      assert {:ok, issues} = Operations.list_admin_import_issues(actor: actor)
      assert Enum.any?(issues, &(&1.issue_code == expected_code))
      refute inspect(issues) =~ "secret-#{status}"
    end
  end

  test "concurrent repeats converge on one issue with the latest occurrence", %{actor: actor} do
    provider = "tcgdex_catalogue"
    base = ~U[2026-01-01 00:00:00.000000Z]

    timestamps = Enum.map(1..10, &DateTime.add(base, &1, :second))

    timestamps
    |> Enum.map(fn timestamp ->
      Task.async(fn ->
        Operations.record_import_issue(
          provider,
          "card_catalogue_sync",
          "set_fetch",
          "set",
          "set-concurrent",
          "failed",
          "timeout",
          timestamp,
          authorize?: false
        )
      end)
    end)
    |> Task.await_many()
    |> Enum.each(&assert({:ok, _issue} = &1))

    assert {:ok, [issue]} = Operations.list_admin_import_issues(actor: actor)
    assert issue.last_seen_at == List.last(timestamps)
  end

  test "invalid values and clocks fail safely" do
    assert {:error, :import_issue_persistence_failed} =
             ImportIssues.record(
               "tcgdex_catalogue",
               "not-an-operation",
               "set_fetch",
               "set",
               "set",
               :timeout,
               fn -> raise "clock secret" end
             )

    for clock <- [fn -> throw(:clock_throw) end, fn -> exit(:clock_exit) end] do
      assert {:error, :import_issue_persistence_failed} =
               ImportIssues.record(
                 "tcgdex_catalogue",
                 "card_catalogue_sync",
                 "set_import",
                 "set",
                 "set",
                 :timeout,
                 clock
               )
    end

    assert {:error, _} =
             Operations.record_import_issue(
               "tcgdex_catalogue",
               "bad",
               "set_fetch",
               "set",
               "set",
               "failed",
               "timeout",
               DateTime.utc_now(),
               authorize?: false
             )

    invalid_matrices = [
      [
        "tcgdex_catalogue",
        "card_catalogue_sync",
        "card_fetch",
        "card",
        "card-1",
        "failed",
        "timeout"
      ],
      [
        "tcgdex_catalogue",
        "card_catalogue_sync",
        "set_fetch",
        "catalogue",
        "tcgdex",
        "failed",
        "timeout"
      ],
      [
        "tcgdex_catalogue",
        "card_catalogue_sync",
        "set_fetch",
        "set",
        "set-1",
        "ambiguous",
        "timeout"
      ]
    ]

    Enum.each(invalid_matrices, fn args ->
      assert {:error, _} =
               apply(
                 Operations,
                 :record_import_issue,
                 args ++ [DateTime.utc_now(), [authorize?: false]]
               )
    end)
  end
end
