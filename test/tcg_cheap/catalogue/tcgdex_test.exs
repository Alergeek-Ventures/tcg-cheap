defmodule TcgCheap.Catalogue.TcgdexTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias TcgCheap.Catalogue.Tcgdex

  defp request_options(name), do: [plug: {Req.Test, name}, retry: false, max_retries: 0]

  test "normalizes fixture responses without provider metadata" do
    name = make_ref()

    Req.Test.stub(name, fn conn ->
      assert conn.request_path == "/v2/en/cards/sv-base-1"
      Req.Test.json(conn, %{"id" => "sv-base-1", "name" => "Pikachu"})
    end)

    assert {:ok, %{"id" => "sv-base-1"} = result} =
             Tcgdex.fetch_card("sv-base-1", request_options: request_options(name))

    refute Map.has_key?(result, "_resource")
  end

  test "rejects malformed, non-200, invalid JSON and unsafe options" do
    name = make_ref()
    Req.Test.stub(name, fn conn -> Plug.Conn.send_resp(conn, 404, "missing") end)

    assert {:error, {:http_error, %{status: 404, kind: "sets", id: "base"}}} =
             Tcgdex.fetch_set("base", request_options: request_options(name))

    name = make_ref()
    Req.Test.stub(name, fn conn -> Req.Test.text(conn, "not json") end)

    assert {:error, {:decode_error, %Jason.DecodeError{}}} =
             Tcgdex.fetch_set("base", request_options: request_options(name))

    name = make_ref()
    Req.Test.stub(name, fn conn -> Req.Test.json(conn, %{"name" => "missing id"}) end)

    assert {:error, {:malformed_response, :missing_id}} =
             Tcgdex.fetch_set("base", request_options: request_options(name))

    assert {:error, :invalid_options} =
             Tcgdex.fetch_card("base", request_options: [max_retries: "2"])

    assert {:error, :invalid_options} =
             Tcgdex.fetch_card("base", request_options: [max_retries: 3])

    assert {:error, :invalid_options} =
             Tcgdex.fetch_card("base", request_options: [retry: false, retry: false])

    assert {:error, :invalid_options} = Tcgdex.fetch_card("base", unknown: true)
    assert {:error, :invalid_options} = Tcgdex.fetch_card("base", [:request_options])
    assert {:error, :invalid_options} = Tcgdex.fetch_card("base", "bad")
  end

  test "caps transient retries at the configured bound" do
    name = make_ref()
    counter = :counters.new(1, [:atomics])

    Req.Test.stub(name, fn conn ->
      _attempt = :counters.add(counter, 1, 1)

      Plug.Conn.send_resp(conn, 503, "temporary")
    end)

    result =
      capture_log(fn ->
        assert {:error, {:http_error, %{status: 503}}} =
                 Tcgdex.fetch_set("base",
                   request_options: [
                     plug: {Req.Test, name},
                     retry: :safe_transient,
                     max_retries: 2
                   ]
                 )
      end)

    assert is_binary(result)

    assert :counters.get(counter, 1) == 3
  end

  test "request admission rejects before HTTP and forces one network attempt" do
    rejected = make_ref()
    Req.Test.stub(rejected, fn _conn -> flunk("rejected request reached HTTP") end)

    assert {:error, {:acquisition_budget_rejected, :provider_disabled}} =
             Tcgdex.fetch_set("base",
               request_options: [
                 plug: {Req.Test, rejected},
                 retry: :safe_transient,
                 max_retries: 2
               ],
               request_admitter: fn ->
                 {:error, {:acquisition_budget_rejected, :provider_disabled}}
               end
             )

    admitted = make_ref()
    attempts = :counters.new(1, [:atomics])

    Req.Test.stub(admitted, fn conn ->
      :counters.add(attempts, 1, 1)
      Plug.Conn.send_resp(conn, 503, "temporary")
    end)

    assert {:error, {:http_error, %{status: 503}}} =
             Tcgdex.fetch_set("base",
               request_options: [
                 plug: {Req.Test, admitted},
                 retry: :safe_transient,
                 max_retries: 2
               ],
               request_admitter: fn -> :ok end
             )

    assert :counters.get(attempts, 1) == 1
  end

  test "lists and normalizes set briefs from the fixed endpoint" do
    name = make_ref()

    Req.Test.stub(name, fn conn ->
      assert conn.request_path == "/v2/en/sets"
      Req.Test.json(conn, [%{"id" => " base ", "name" => " Base "}])
    end)

    assert {:ok, [%{"id" => "base", "name" => "Base"}]} =
             Tcgdex.list_sets(request_options: request_options(name))
  end

  test "rejects malformed set lists, duplicate/noncanonical IDs, and non-200 responses" do
    for body <- [
          %{"id" => "base", "name" => "Base"},
          [%{"id" => "bad id", "name" => "Bad"}],
          [%{"id" => "base", "name" => "Base"}, %{"id" => " base ", "name" => "Again"}]
        ] do
      name = make_ref()
      Req.Test.stub(name, fn conn -> Req.Test.json(conn, body) end)

      assert {:error, {:malformed_response, _}} =
               Tcgdex.list_sets(request_options: request_options(name))
    end

    name = make_ref()
    Req.Test.stub(name, fn conn -> Plug.Conn.send_resp(conn, 503, "offline") end)

    assert {:error, {:http_error, %{status: 503, kind: "sets", id: nil}}} =
             Tcgdex.list_sets(request_options: request_options(name))
  end

  test "rejects non-array set roots and unsafe list options without raising" do
    name = make_ref()
    Req.Test.stub(name, fn conn -> Req.Test.json(conn, %{"id" => "base"}) end)

    assert {:error, {:malformed_response, :expected_array}} =
             Tcgdex.list_sets(request_options: request_options(name))

    assert {:error, :invalid_options} = Tcgdex.list_sets("bad")
    assert {:error, :invalid_options} = Tcgdex.list_sets(request_options: [], request_options: [])
    assert {:error, :invalid_options} = Tcgdex.list_sets(unknown: true)
  end
end
