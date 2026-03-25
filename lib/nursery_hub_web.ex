defmodule NurseryHubWeb do
  def controller do
    quote do
      use Phoenix.Controller, namespace: NurseryHubWeb
      import Plug.Conn
    end
  end

  def router do
    quote do
      use Phoenix.Router, helpers: false
      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView, layout: {NurseryHubWeb.Layouts, :app}
    end
  end

  def html do
    quote do
      use Phoenix.Component
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
