defmodule TcgCheap.Core do
  @moduledoc """
  Ash domain reserved for the application's resources.

  It is intentionally empty during bootstrap.
  """

  use Ash.Domain,
    otp_app: :tcg_cheap

  resources do
  end
end
