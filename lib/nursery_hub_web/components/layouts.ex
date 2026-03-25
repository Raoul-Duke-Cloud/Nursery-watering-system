defmodule NurseryHubWeb.Layouts do
  use Phoenix.Component

  def render("root.html", assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1"/>
        <title>NurseryHub</title>
        <script src="https://cdn.tailwindcss.com"></script>
        <script src="https://cdn.jsdelivr.net/npm/chart.js@4/dist/chart.umd.min.js"></script>
        <script src="https://cdn.jsdelivr.net/npm/phoenix@1.7.14/priv/static/phoenix.min.js"></script>
        <script src="https://cdn.jsdelivr.net/npm/phoenix_live_view@0.20.17/priv/static/phoenix_live_view.min.js"></script>
        <script>
          const lv = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket)
          lv.connect()
        </script>
      </head>
      <body class="bg-gray-950 text-gray-100 min-h-screen">
        <%= @inner_content %>
      </body>
    </html>
    """
  end
end
