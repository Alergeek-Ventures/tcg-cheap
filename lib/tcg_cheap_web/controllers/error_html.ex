defmodule TcgCheapWeb.ErrorHTML do
  @moduledoc """
  The endpoint's error responses for HTML requests: a plain text page with the
  status message, "Not Found" for "404.html".
  """
  use TcgCheapWeb, :html

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
