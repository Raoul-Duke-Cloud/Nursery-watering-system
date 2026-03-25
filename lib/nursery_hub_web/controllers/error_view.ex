defmodule NurseryHubWeb.ErrorView do
  def render("404.html", _), do: "404 - Not found"
  def render("500.html", _), do: "500 - Server error"
  def render(_, _),          do: "Error"
end
