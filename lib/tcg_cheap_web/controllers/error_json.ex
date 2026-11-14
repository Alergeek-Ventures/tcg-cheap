defmodule TcgCheapWeb.ErrorJSON do
  @moduledoc """
  The endpoint's error responses for JSON requests: the status message, as in
  `%{errors: %{detail: "Not Found"}}` for "404.json".
  """

  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
