# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :anoma_explorer,
  ecto_repos: [AnomaExplorer.Repo],
  generators: [timestamp_type: :utc_datetime],
  env: config_env()

# Configure the endpoint
config :anoma_explorer, AnomaExplorerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Phoenix.Endpoint.Cowboy2Adapter,
  render_errors: [
    formats: [html: AnomaExplorerWeb.ErrorHTML, json: AnomaExplorerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: AnomaExplorer.PubSub,
  live_view: [signing_salt: "zK0ouHY9"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  anoma_explorer: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{
      "NODE_PATH" =>
        Enum.join(
          [
            Path.expand("../deps", __DIR__),
            Path.expand("../_build/#{Mix.env()}", __DIR__)
          ],
          ":"
        )
    }
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  anoma_explorer: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
