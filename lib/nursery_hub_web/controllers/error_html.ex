defmodule NurseryHubWeb.ErrorHTML do
  use Phoenix.Component

  def render("404.html", assigns) do
    ~H"""
    <!DOCTYPE html>
    <html>
      <head><title>Not Found</title></head>
      <body style="background:#0a0a0a;color:#ccc;font-family:sans-serif;text-align:center;padding:4rem">
        <h1>404 — Page not found</h1>
      </body>
    </html>
    """
  end

  def render("500.html", assigns) do
    ~H"""
    <!DOCTYPE html>
    <html>
      <head><title>Server Error</title></head>
      <body style="background:#0a0a0a;color:#ccc;font-family:sans-serif;text-align:center;padding:4rem">
        <h1>500 — Something went wrong</h1>
      </body>
    </html>
    """
  end

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
