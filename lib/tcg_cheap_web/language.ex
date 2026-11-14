defmodule TcgCheapWeb.Language do
  @moduledoc """
  A language the guide renders in, one module per language in
  `lib/tcg_cheap_web/languages/` (`TcgCheapWeb.Languages`): its name and how
  it writes dates and decimals (`TcgCheapWeb.Format`). Its text is its
  Gettext locale, `priv/gettext/<code>/`.
  """

  @doc ~S(The Gettext locale and `lang` attribute: "hu".)
  @callback code() :: String.t()

  @doc ~S(The language under its own name, for the language control: "Magyar".)
  @callback name() :: String.t()

  @doc ~S(A full date: "17 lipca 2026", "17 July 2026", "2026. július 17.".)
  @callback date(Date.t()) :: String.t()

  @doc ~S(A day and month: "6 listopada", "6 November", "november 6.".)
  @callback day_month(Date.t()) :: String.t()

  @doc ~S(Days of one month, from the first to the second: "2–8 listopada", "november 2–8.".)
  @callback days_in_month(Date.t(), Date.t()) :: String.t()

  @doc ~S(A short date for chart axes: "17 lip", "17 Jul", "júl. 17.", with a no-break space.)
  @callback short_date(Date.t()) :: String.t()

  @doc ~S(The decimal separator of numbers in text: "," or ".".)
  @callback decimal_separator() :: String.t()

  @doc ~S(A language's name as it reads mid-sentence: "angielska" in Polish, "English" in English.)
  @callback mid_sentence(String.t()) :: String.t()
end
