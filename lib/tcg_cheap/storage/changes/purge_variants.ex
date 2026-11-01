defmodule TcgCheap.Storage.Changes.PurgeVariants do
  @moduledoc """
  Purges a blob's variants (files and records) before the blob is destroyed.

  AshStorage does not clean variants up on its own, and their foreign key to
  the source blob would otherwise block destroying it.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    context_opts = Ash.Context.to_opts(context)

    Ash.Changeset.before_action(changeset, fn changeset ->
      with {:ok, blob} <- Ash.load(changeset.data, :variants, context_opts),
           :ok <- purge_all(blob.variants, context_opts) do
        changeset
      else
        {:error, error} -> Ash.Changeset.add_error(changeset, error)
      end
    end)
  end

  @impl true
  def atomic(_changeset, _opts, _context) do
    {:not_atomic, "purging variant files requires the blob being destroyed"}
  end

  defp purge_all(variants, context_opts) do
    Enum.reduce_while(variants, :ok, fn variant, :ok ->
      case Ash.destroy(variant, Keyword.put(context_opts, :action, :purge_blob)) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
