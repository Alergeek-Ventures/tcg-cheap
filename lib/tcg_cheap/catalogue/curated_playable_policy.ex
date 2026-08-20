defmodule TcgCheap.Catalogue.CuratedPlayablePolicy do
  @moduledoc "The fixed, approval-gated curated playable collection manifest."

  @evidence_version "2026-08-19-naic"
  @evidence_date ~D[2026-08-19]
  @expires_on ~D[2026-11-17]

  @entries [
    %{
      tcgdex_id: "me01-131",
      name: "Ultra Ball",
      set_id: "me01",
      category: "Trainer",
      trainer_type: "Item",
      regulation_mark: "I",
      collector_number: "131"
    },
    %{
      tcgdex_id: "sv05-144",
      name: "Buddy-Buddy Poffin",
      set_id: "sv05",
      category: "Trainer",
      trainer_type: "Item",
      regulation_mark: "H",
      collector_number: "144"
    },
    %{
      tcgdex_id: "sv05-157",
      name: "Prime Catcher",
      set_id: "sv05",
      category: "Trainer",
      trainer_type: "Item",
      regulation_mark: "H",
      collector_number: "157"
    },
    %{
      tcgdex_id: "sv06-165",
      name: "Unfair Stamp",
      set_id: "sv06",
      category: "Trainer",
      trainer_type: "Item",
      regulation_mark: "H",
      collector_number: "165"
    },
    %{
      tcgdex_id: "sv07-133",
      name: "Crispin",
      set_id: "sv07",
      category: "Trainer",
      trainer_type: "Supporter",
      regulation_mark: "H",
      collector_number: "133"
    },
    %{
      tcgdex_id: "me01-114",
      name: "Boss's Orders",
      set_id: "me01",
      category: "Trainer",
      trainer_type: "Supporter",
      regulation_mark: "I",
      collector_number: "114"
    },
    %{
      tcgdex_id: "me01-119",
      name: "Lillie's Determination",
      set_id: "me01",
      category: "Trainer",
      trainer_type: "Supporter",
      regulation_mark: "I",
      collector_number: "119"
    }
  ]

  def evidence_version, do: @evidence_version
  def evidence_date, do: @evidence_date
  def expires_on, do: @expires_on
  def entries, do: @entries
  def entry(id) when is_binary(id), do: Enum.find(@entries, &(&1.tcgdex_id == id))
  def entry(_), do: nil

  def valid_on?(%Date{} = as_of),
    do: Date.compare(as_of, @evidence_date) != :lt and Date.compare(as_of, @expires_on) != :gt

  def valid_on?(_), do: false

  def status(%Date{} = as_of) do
    cond do
      Date.compare(as_of, @evidence_date) == :lt -> :before_evidence
      Date.compare(as_of, @expires_on) == :gt -> :after_expiry
      true -> :active
    end
  end

  def status(_), do: :invalid
end
