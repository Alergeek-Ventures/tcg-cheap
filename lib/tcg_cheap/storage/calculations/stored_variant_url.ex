defmodule TcgCheap.Storage.Calculations.StoredVariantUrl do
  @moduledoc """
  URL of an attachment's variant once it is stored, else `nil`.

  Unlike AshStorage's own `<attachment>_<variant>_url`, it never generates a
  missing variant while a page renders: a variant added to existing photos is
  filled in by a background job (`TcgCheap.Sealed.PhotoMirror`).
  """

  use Ash.Resource.Calculation

  alias AshStorage.Service.Context
  alias AshStorage.VariantDefinition

  @impl true
  def strict_loads?, do: false

  @impl true
  def load(_query, opts, _context), do: [{opts[:attachment], blob: :variants}]

  @impl true
  def calculate([], _opts, _context), do: []

  def calculate([record | _] = records, opts, _context) do
    resource = record.__struct__
    {:ok, attachment_def} = AshStorage.Info.attachment(resource, opts[:attachment])
    variant_def = Enum.find(attachment_def.variants, &(&1.name == opts[:variant]))
    name = to_string(variant_def.name)
    digest = VariantDefinition.digest(variant_def)

    {:ok, {service, service_opts}} =
      AshStorage.Info.service_for_attachment(resource, attachment_def)

    ctx = Context.new(service_opts, resource: resource, attachment: attachment_def)

    Enum.map(records, fn record ->
      with %{blob: %{variants: variants}} <- Map.get(record, opts[:attachment]),
           %{key: key} <-
             Enum.find(variants, &(&1.variant_name == name and &1.variant_digest == digest)) do
        service.url(key, ctx)
      else
        _missing -> nil
      end
    end)
  end
end
