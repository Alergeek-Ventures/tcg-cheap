defmodule TcgCheapWeb.HomeLive do
  use TcgCheapWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "TCG Cheap")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="space-y-4">
        <h1 class="text-3xl font-bold">TCG Cheap</h1>
        <p class="text-lg">Ash + LiveView foundation ready.</p>
      </section>
    </Layouts.app>
    """
  end
end
