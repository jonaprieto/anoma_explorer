defmodule AnomaExplorerWeb.PageController do
  use AnomaExplorerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def settings_redirect(conn, _params) do
    redirect(conn, to: "/settings/contracts")
  end
end
