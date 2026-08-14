defmodule TcgCheap.Operations.ImportIssueTest do
  use TcgCheap.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias TcgCheap.Accounts.Admin
  alias TcgCheap.Operations
  alias TcgCheap.Operations.ImportIssues
  alias TcgCheap.Repo

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

  test "resolution watermarks require explicit internal authorization" do
    assert {:error, _} = Operations.get_catalogue_set_issue_resolution("set", "all")

    assert {:error, _} =
             Operations.record_catalogue_set_issue_resolution(
               "set",
               "all",
               ~U[2026-01-01 00:00:00Z]
             )

    assert {:ok, nil} =
             Operations.get_catalogue_set_issue_resolution("set", "all", authorize?: false)
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
      apply(Operations, :record_import_issue, args ++ [timestamp, nil, [authorize?: false]])
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

  test "resolution is retained, older evidence does not reopen, and newer evidence does" do
    first = ~U[2026-01-01 00:00:00.000000Z]
    delayed = ~U[2026-01-01 00:00:05.000000Z]
    resolved = ~U[2026-01-01 00:00:10.000000Z]
    newer = ~U[2026-01-01 00:00:20.000000Z]

    assert :ok =
             ImportIssues.record(
               "tcgdex_catalogue",
               "card_catalogue_sync",
               "set_fetch",
               "set",
               "resolve-set",
               :timeout,
               first
             )

    assert :ok = ImportIssues.resolve_catalogue_set("resolve-set", resolved)
    assert {:ok, []} = Operations.list_unresolved_catalogue_set("resolve-set", authorize?: false)

    assert :ok =
             ImportIssues.record(
               "tcgdex_catalogue",
               "card_catalogue_sync",
               "set_fetch",
               "set",
               "resolve-set",
               :timeout,
               delayed
             )

    assert {:ok, []} = Operations.list_unresolved_catalogue_set("resolve-set", authorize?: false)

    assert :ok =
             ImportIssues.record(
               "tcgdex_catalogue",
               "card_catalogue_sync",
               "set_fetch",
               "set",
               "resolve-set",
               :timeout,
               newer
             )

    assert {:ok, [issue]} =
             Operations.list_unresolved_catalogue_set("resolve-set", authorize?: false)

    assert issue.last_seen_at == newer
    assert issue.resolved_at == nil
  end

  test "delayed hard evidence with a different identity inherits the resolution watermark" do
    resolved_at = ~U[2026-01-01 00:00:10Z]

    assert :ok =
             ImportIssues.record(
               "tcgdex_catalogue",
               "card_catalogue_sync",
               "set_fetch",
               "set",
               "watermark-set",
               :timeout,
               ~U[2026-01-01 00:00:01Z]
             )

    assert :ok = ImportIssues.resolve_catalogue_set("watermark-set", resolved_at)

    assert :ok =
             ImportIssues.record(
               "tcgdex_catalogue",
               "card_catalogue_sync",
               "set_validation",
               "set",
               "watermark-set",
               :malformed_response,
               ~U[2026-01-01 00:00:05Z]
             )

    assert {:ok, []} =
             Operations.list_unresolved_catalogue_set("watermark-set", authorize?: false)

    assert :ok =
             ImportIssues.record(
               "tcgdex_catalogue",
               "card_catalogue_sync",
               "set_import",
               "set",
               "watermark-set",
               :provider_callback_error,
               ~U[2026-01-01 00:00:11Z]
             )

    assert {:ok, [_issue]} =
             Operations.list_unresolved_catalogue_set("watermark-set", authorize?: false)
  end

  test "a partial issue at the resolution timestamp remains unresolved" do
    timestamp = ~U[2026-01-01 00:00:10Z]

    assert :ok =
             ImportIssues.record(
               "tcgdex_catalogue",
               "card_catalogue_sync",
               "set_fetch",
               "set",
               "partial-watermark-set",
               :timeout,
               ~U[2026-01-01 00:00:01Z]
             )

    assert :ok = ImportIssues.resolve_catalogue_set("partial-watermark-set", timestamp)

    assert :ok =
             ImportIssues.record(
               "tcgdex_catalogue",
               "card_catalogue_sync",
               "set_validation",
               "set",
               "partial-watermark-set",
               {:partial_coverage, :current},
               timestamp
             )

    assert {:ok, [issue]} =
             Operations.list_unresolved_catalogue_set("partial-watermark-set", authorize?: false)

    assert issue.issue_kind == "partial"
  end

  test "barrier-started record and resolution races preserve timestamp semantics" do
    timestamp = ~U[2026-01-01 00:00:10Z]

    cases =
      Enum.map(
        [
          {"older-hard", :timeout, ~U[2026-01-01 00:00:09Z], false},
          {"equal-hard", :timeout, timestamp, false},
          {"newer-hard", :timeout, ~U[2026-01-01 00:00:11Z], true},
          {"equal-partial", {:partial_coverage, :equal}, timestamp, true}
        ],
        fn {label, reason, evidence_at, unresolved?} ->
          {"race-#{label}-#{System.unique_integer([:positive])}", reason, evidence_at,
           unresolved?}
        end
      )

    set_ids = Enum.map(cases, &elem(&1, 0))

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Repo.query!("DELETE FROM import_issues WHERE target_key = ANY($1)", [set_ids])

        Repo.query!("DELETE FROM catalogue_set_issue_resolutions WHERE set_id = ANY($1)", [
          set_ids
        ])
      end)
    end)

    for {set_id, reason, evidence_at, unresolved?} <- cases do
      results =
        concurrently([
          fn ->
            ImportIssues.record(
              "tcgdex_catalogue",
              "card_catalogue_sync",
              "set_fetch",
              "set",
              set_id,
              reason,
              evidence_at
            )
          end,
          fn -> ImportIssues.resolve_catalogue_set(set_id, timestamp) end
        ])

      assert Enum.all?(results, &(&1 in [:ok, {:error, :import_issue_resolution_failed}]))

      {:ok, issues} = Operations.list_unresolved_catalogue_set(set_id, authorize?: false)
      assert issues != [] == unresolved?
    end
  end

  test "resolution rejects invalid set IDs, clocks, and timestamps before latest evidence" do
    latest = ~U[2026-01-01 00:00:10Z]

    assert :ok =
             ImportIssues.record(
               "tcgdex_catalogue",
               "card_catalogue_sync",
               "set_fetch",
               "set",
               "resolve-invalid",
               :timeout,
               latest
             )

    assert {:error, :import_issue_resolution_failed} =
             ImportIssues.resolve_catalogue_set("bad id", latest)

    assert {:error, :import_issue_resolution_failed} =
             ImportIssues.resolve_catalogue_set("resolve-invalid", ~U[2026-01-01 00:00:09Z])

    assert {:error, :import_issue_resolution_failed} =
             ImportIssues.resolve_catalogue_set("resolve-invalid", :not_a_timestamp)
  end

  test "catalogue-set resolution leaves unmatched and ambiguous diagnostics unresolved" do
    timestamp = ~U[2026-01-01 00:00:00Z]

    for {set_id, reason} <- [
          {"unmatched-set", :unmatched_external_mapping},
          {"ambiguous-set", :ambiguous_external_mapping}
        ] do
      assert :ok =
               ImportIssues.record(
                 "tcgdex_catalogue",
                 "card_catalogue_sync",
                 "set_fetch",
                 "set",
                 set_id,
                 reason,
                 timestamp
               )

      assert :ok = ImportIssues.resolve_catalogue_set(set_id, timestamp)
      assert {:ok, issues} = Operations.list_admin_import_issues(authorize?: false)
      assert [issue] = Enum.filter(issues, &(&1.target_key == set_id))
      assert issue.issue_kind in ["unmatched", "ambiguous"]
      assert is_nil(issue.resolved_at)
    end
  end

  test "catalogue-set resolution updates multiple relevant issue rows" do
    timestamp = ~U[2026-01-01 00:00:00Z]
    set_id = "multi-row-set"

    for stage <- ["set_fetch", "set_validation"] do
      assert :ok =
               ImportIssues.record(
                 "tcgdex_catalogue",
                 "card_catalogue_sync",
                 stage,
                 "set",
                 set_id,
                 :timeout,
                 timestamp
               )
    end

    assert :ok = ImportIssues.resolve_catalogue_set(set_id, timestamp)
    assert {:ok, []} = Operations.list_unresolved_catalogue_set(set_id, authorize?: false)
  end

  test "unresolved catalogue IDs are unique, sorted, and bounded" do
    for {id, stage} <- [
          {"z-set", "set_fetch"},
          {"a-set", "set_fetch"},
          {"z-set", "set_validation"}
        ] do
      assert :ok =
               ImportIssues.record(
                 "tcgdex_catalogue",
                 "card_catalogue_sync",
                 stage,
                 "set",
                 id,
                 :timeout,
                 DateTime.utc_now()
               )
    end

    assert {:ok, issues} = Operations.list_unresolved_catalogue_sets(authorize?: false)
    assert Enum.map(issues, & &1.target_key) == ["a-set", "z-set"]
    assert {:ok, ["a-set", "z-set"]} = ImportIssues.unresolved_catalogue_set_ids()
  end

  test "unresolved catalogue IDs fail closed when the bounded read overflows" do
    timestamp = ~U[2026-01-01 00:00:00Z]

    for index <- 1..1001 do
      assert :ok =
               ImportIssues.record(
                 "tcgdex_catalogue",
                 "card_catalogue_sync",
                 "set_fetch",
                 "set",
                 "overflow-#{index}",
                 :timeout,
                 timestamp
               )
    end

    assert {:error, :import_issue_read_failed} = ImportIssues.unresolved_catalogue_set_ids()
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
               apply(
                 Operations,
                 :record_import_issue,
                 args ++ [timestamp, nil, [authorize?: false]]
               )
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
          nil,
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
               nil,
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
                 args ++ [DateTime.utc_now(), nil, [authorize?: false]]
               )
    end)
  end

  defp concurrently(functions) do
    parent = self()

    workers =
      Enum.map(functions, fn function ->
        spawn(fn ->
          send(parent, {:ready, self()})

          receive do
            :go -> send(parent, {:done, self(), Sandbox.unboxed_run(Repo, function)})
          end
        end)
      end)

    Enum.each(workers, fn worker -> assert_receive {:ready, ^worker}, 5_000 end)
    Enum.each(workers, &send(&1, :go))

    Enum.map(workers, fn worker ->
      assert_receive {:done, ^worker, result}, 10_000
      result
    end)
  end
end
