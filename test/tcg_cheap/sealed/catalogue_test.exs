defmodule TcgCheap.Sealed.CatalogueTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Catalogue.ExternalImage
  alias TcgCheap.Sealed.{Catalogue, Matcher}

  test "slugs are unique and URL safe" do
    slugs = Enum.map(Catalogue.all(), & &1.slug)
    assert slugs == Enum.uniq(slugs)
    assert Enum.all?(slugs, &String.match?(&1, ~r/\A[a-z0-9]+(-[a-z0-9]+)*\z/))
  end

  test "keeps the 19 previously curated production slugs" do
    for slug <- ~w(
          pokemon-tcg-pitch-black-3-pack-blister-binacle pokemon-tcg-pitch-black-booster-box
          pokemon-tcg-pitch-black-booster-pack pokemon-tcg-pitch-black-elite-trainer-box
          pokemon-tcg-mega-evolution-chaos-rising-booster-box
          pokemon-tcg-mega-evolution-chaos-rising-booster-pack
          pokemon-tcg-mega-evolution-chaos-rising-elite-trainer-box
          pokemon-tcg-mega-evolution-ascended-heroes-booster-bundle
          pokemon-tcg-mega-evolution-ascended-heroes-elite-trainer-box
          pokemon-tcg-scarlet-violet-destined-rivals-booster-box
          pokemon-tcg-scarlet-violet-destined-rivals-booster-pack
          pokemon-tcg-scarlet-violet-destined-rivals-elite-trainer-box
          pokemon-tcg-scarlet-violet-151-booster-bundle
          pokemon-tcg-scarlet-violet-stellar-crown-booster-pack
          pokemon-tcg-scarlet-violet-twilight-masquerade-booster-pack
          pokemon-tcg-scarlet-violet-temporal-forces-booster-pack
          pokemon-tcg-scarlet-violet-paradox-rift-booster-pack
          pokemon-tcg-scarlet-violet-obsidian-flames-booster-pack
          pokemon-tcg-pokemon-day-2026-collection
        ) do
      assert {:ok, _product} = Catalogue.get(slug), slug
    end
  end

  test "every term and exclusion is already normalized" do
    for product <- Catalogue.all(),
        phrase <- List.flatten(product.terms) ++ product.exclude do
      assert Matcher.normalize(phrase) == phrase, "#{product.slug}: #{phrase}"
    end
  end

  test "every product has terms, a known kind and an allowed image" do
    for product <- Catalogue.all() do
      assert product.terms != [], product.slug
      assert product.kind in Catalogue.kinds()
      assert is_nil(product.image_url) or ExternalImage.valid?(product.image_url), product.slug
    end
  end

  test "lists the newest releases first and undated products last" do
    dates = Enum.map(Catalogue.all(), & &1.release_date)
    {dated, undated} = Enum.split_while(dates, & &1)
    assert dated == Enum.sort(dated, {:desc, Date})
    assert Enum.all?(undated, &is_nil/1)
  end

  test "search matches word prefixes of name, set and kind" do
    assert Enum.map(Catalogue.search("pitch black box"), & &1.slug) == [
             "pokemon-tcg-pitch-black-elite-trainer-box",
             "pokemon-tcg-pitch-black-booster-box"
           ]

    assert Catalogue.search("kolek") |> Enum.all?(&(&1.kind == :collection))

    assert Catalogue.search("pokémon day") |> Enum.map(& &1.slug) == [
             "pokemon-tcg-pokemon-day-2026-collection"
           ]

    assert Catalogue.search("zzz") == []
    assert Catalogue.search("  ") == Catalogue.all()
  end
end
