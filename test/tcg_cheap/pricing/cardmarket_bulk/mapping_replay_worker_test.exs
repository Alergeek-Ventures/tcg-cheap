defmodule TcgCheap.Pricing.CardmarketBulk.MappingReplayWorkerTest do
  use TcgCheap.DataCase, async: false

  alias TcgCheap.Pricing.CardmarketBulk.Batch
  alias TcgCheap.Pricing.CardmarketBulk.MappingReplayWorker

  test "replay rejects non-succeeded batches" do
    assert {:error, :batch_not_succeeded} =
             MappingReplayWorker.replay_succeeded_batch(%Batch{status: "staged"})

    assert {:error, :batch_not_succeeded} =
             MappingReplayWorker.replay_succeeded_batch(%Batch{status: "failed"})
  end

  test "discards malformed arguments before persistence" do
    assert {:discard, :malformed_job_args} =
             MappingReplayWorker.perform(%Oban.Job{args: %{"batch_id" => 42}})

    assert {:discard, :malformed_job_args} =
             MappingReplayWorker.perform(%Oban.Job{
               args: %{"batch_id" => "not-a-uuid", "decision_id" => Ecto.UUID.generate()}
             })
  end

  test "discards a valid decision id when no matching decision exists" do
    batch_id = Ecto.UUID.generate()
    decision_id = Ecto.UUID.generate()

    assert {:discard, :decision_not_found} =
             MappingReplayWorker.perform(%Oban.Job{
               args: %{"batch_id" => batch_id, "decision_id" => decision_id}
             })
  end
end
