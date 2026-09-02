defmodule TcgCheap.Catalogue.Validations.SealedProductFields do
  @moduledoc "Validates sealed product factual fields and provenance invariants."
  use Ash.Resource.Validation

  alias Ash.Changeset
  alias TcgCheap.Catalogue.{ExternalImage, ExternalUrl}

  @impl true
  def validate(changeset, _opts, _context) do
    validations = [
      fn ->
        validate_values(
          Changeset.get_attribute(changeset, :msrp_pln),
          Changeset.get_attribute(changeset, :msrp_source)
        )
      end,
      fn ->
        validate_url(:msrp_source_url, Changeset.get_attribute(changeset, :msrp_source_url))
      end,
      fn -> validate_url(:official_url, Changeset.get_attribute(changeset, :official_url)) end,
      fn -> validate_official_price(changeset) end,
      fn -> validate_image(changeset) end,
      fn -> validate_details(changeset) end
    ]

    run_validations(validations)
  end

  defp run_validations([]), do: :ok

  defp run_validations([validation | remaining]) do
    case validation.() do
      :ok -> run_validations(remaining)
      error -> error
    end
  end

  def validate_values(amount, source) do
    cond do
      is_nil(amount) and is_nil(source) ->
        :ok

      valid_amount?(amount) and is_binary(source) and String.trim(source) != "" ->
        :ok

      not is_nil(amount) and not valid_amount?(amount) ->
        {:error, field: :msrp_pln, message: "must be a finite positive amount"}

      true ->
        {:error,
         field: :msrp_source,
         message: "is required when MSRP is present and cannot exist without MSRP"}
    end
  end

  defp valid_amount?(%Decimal{} = amount) do
    not Decimal.nan?(amount) and not Decimal.inf?(amount) and
      Decimal.compare(amount, Decimal.new(0)) == :gt
  end

  defp valid_amount?(_), do: false

  defp validate_url(_field, nil), do: :ok

  defp validate_url(field, value) do
    if ExternalUrl.valid?(value),
      do: :ok,
      else: {:error, field: field, message: "must be a safe HTTPS URL"}
  end

  defp validate_required_url(field, nil),
    do: {:error, field: field, message: "must be a safe HTTPS URL"}

  defp validate_required_url(field, value), do: validate_url(field, value)

  defp validate_official_price(changeset) do
    amount = Changeset.get_attribute(changeset, :official_price_amount)
    currency = Changeset.get_attribute(changeset, :official_price_currency)
    source = Changeset.get_attribute(changeset, :official_price_source)
    url = Changeset.get_attribute(changeset, :official_price_source_url)

    validate_official_price_values(amount, currency, source, url)
  end

  defp validate_official_price_values(nil, nil, nil, nil), do: :ok

  defp validate_official_price_values(amount, _currency, _source, _url)
       when not is_struct(amount, Decimal),
       do: {:error, field: :official_price_amount, message: "must be finite and positive"}

  defp validate_official_price_values(amount, currency, source, url)
       when is_struct(amount, Decimal) do
    if valid_amount?(amount),
      do: validate_official_price_remainder(currency, source, url),
      else: {:error, field: :official_price_amount, message: "must be finite and positive"}
  end

  defp validate_official_price_remainder(currency, _source, _url)
       when currency not in ~w(PLN USD EUR),
       do: {:error, field: :official_price_currency, message: "must be PLN, USD, or EUR"}

  defp validate_official_price_remainder(_currency, source, _url)
       when not is_binary(source),
       do: {:error, field: :official_price_source, message: "is required"}

  defp validate_official_price_remainder(_currency, source, url)
       when is_binary(source) do
    if String.trim(source) == "",
      do: {:error, field: :official_price_source, message: "is required"},
      else: validate_required_url(:official_price_source_url, url)
  end

  defp validate_image(changeset) do
    image = Changeset.get_attribute(changeset, :image_url)
    source = Changeset.get_attribute(changeset, :image_source)
    source_url = Changeset.get_attribute(changeset, :image_source_url)

    validate_image_presence(image, source, source_url)
  end

  defp validate_image_presence(image, source, source_url) do
    if Enum.all?([image, source, source_url], &empty_image_field?/1),
      do: :ok,
      else: validate_image_present(image, source, source_url)
  end

  defp empty_image_field?(nil), do: true
  defp empty_image_field?(%Ash.NotLoaded{}), do: true
  defp empty_image_field?(_), do: false

  defp validate_image_present(image, source, source_url) do
    cond do
      not ExternalImage.valid?(image) ->
        {:error, field: :image_url, message: "must be an allowed HTTPS image URL"}

      not is_binary(source) or String.trim(source) == "" ->
        {:error, field: :image_source, message: "is required"}

      not ExternalUrl.valid?(source_url) ->
        {:error, field: :image_source_url, message: "must be a safe HTTPS URL"}

      true ->
        :ok
    end
  end

  defp validate_details(changeset) do
    description = Changeset.get_attribute(changeset, :description)

    contents =
      case Changeset.get_attribute(changeset, :contents) do
        %Ash.NotLoaded{} -> []
        nil -> []
        value -> value
      end

    pack_count = Changeset.get_attribute(changeset, :pack_count)
    cards_per_pack = Changeset.get_attribute(changeset, :cards_per_pack)
    official_url = Changeset.get_attribute(changeset, :official_url)
    source = Changeset.get_attribute(changeset, :details_source)
    source_url = Changeset.get_attribute(changeset, :details_source_url)

    validate_details_presence(
      description,
      contents,
      pack_count,
      cards_per_pack,
      official_url,
      source,
      source_url
    )
  end

  defp validate_details_presence(nil, [], nil, nil, nil, nil, nil), do: :ok

  defp validate_details_presence(
         _description,
         contents,
         pack_count,
         cards_per_pack,
         official_url,
         source,
         source_url
       ),
       do:
         run_validations([
           fn -> validate_contents(contents) end,
           fn -> validate_count(:pack_count, pack_count) end,
           fn -> validate_count(:cards_per_pack, cards_per_pack) end,
           fn -> validate_source(source) end,
           fn -> validate_required_url(:details_source_url, source_url) end,
           fn -> validate_optional_url(:official_url, official_url) end
         ])

  defp validate_contents(contents)
       when is_list(contents) and length(contents) <= 20 do
    if Enum.all?(contents, &(is_binary(&1) and String.trim(&1) != "" and byte_size(&1) <= 240)),
      do: :ok,
      else: contents_error()
  end

  defp validate_contents(_), do: contents_error()

  defp contents_error,
    do:
      {:error,
       field: :contents, message: "must contain at most 20 nonblank strings of 240 bytes or fewer"}

  defp validate_count(_field, nil), do: :ok

  defp validate_count(_field, value) when is_integer(value) and value in 1..100, do: :ok

  defp validate_count(field, _value),
    do: {:error, field: field, message: "must be between 1 and 100"}

  defp validate_source(source) when is_binary(source) do
    if String.trim(source) == "",
      do: {:error, field: :details_source, message: "is required"},
      else: :ok
  end

  defp validate_source(_), do: {:error, field: :details_source, message: "is required"}

  defp validate_optional_url(_field, nil), do: :ok
  defp validate_optional_url(field, value), do: validate_url(field, value)
end
