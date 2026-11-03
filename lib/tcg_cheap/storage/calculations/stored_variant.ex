defmodule TcgCheap.Storage.Calculations.StoredVariant do
  @moduledoc """
  An attachment's stored variant: its URL (`value: :url`) or its inline
  placeholder (`value: :placeholder`, see `TcgCheap.Storage.Variants.Webp`),
  else `nil`.

  Unlike AshStorage's own `<attachment>_<variant>_url`, it never generates a
  missing variant while a page renders, so it loads only the few columns of
  the variant blobs it reads: a variant missing for a stored photo is filled
  in by a background job (`TcgCheap.Sealed.PhotoMirror`).
  """

  use Ash.Resource.Calculation

  alias AshStorage.Service.Context
  alias AshStorage.VariantDefinition
  alias TcgCheap.Storage.{Attachment, Blob}

  @impl true
  def strict_loads?, do: false

  @impl true
  def load(_query, opts, _context) do
    variants = Ash.Query.select(Blob, [:key, :variant_name, :variant_digest, :placeholder])
    blob = Blob |> Ash.Query.select([]) |> Ash.Query.load(variants: variants)
    [{opts[:attachment], Attachment |> Ash.Query.select([]) |> Ash.Query.load(blob: blob)}]
  end

  @impl true
  def calculate([], _opts, _context), do: []

  def calculate([record | _] = records, opts, _context) do
    resource = record.__struct__
    {:ok, attachment_def} = AshStorage.Info.attachment(resource, opts[:attachment])
    variant_def = Enum.find(attachment_def.variants, &(&1.name == opts[:variant]))
    name = to_string(variant_def.name)
    digest = VariantDefinition.digest(variant_def)
    value = value_fun(opts[:value], resource, attachment_def)

    Enum.map(records, fn record ->
      with %{blob: %{variants: variants}} <- Map.get(record, opts[:attachment]),
           %{} = variant <-
             Enum.find(variants, &(&1.variant_name == name and &1.variant_digest == digest)) do
        value.(variant)
      else
        _missing -> nil
      end
    end)
  end

  defp value_fun(:placeholder, _resource, _attachment_def), do: & &1.placeholder

  defp value_fun(:url, resource, attachment_def) do
    {:ok, {service, service_opts}} =
      AshStorage.Info.service_for_attachment(resource, attachment_def)

    ctx = Context.new(service_opts, resource: resource, attachment: attachment_def)
    &service.url(&1.key, ctx)
  end
end
