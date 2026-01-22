# Anoma Explorer

Anoma Explorer is a Phoenix LiveView application for visualising Anoma Protocol activity across supported EVM networks, backed by an Envio Hyperindex GraphQL indexer.

## Features

- Dashboard with aggregate statistics and recent transactions
- Explorer views for transactions, resources, actions, compliance units, logic inputs, commitment roots, and nullifiers
- GraphQL playground for ad-hoc queries against the configured Envio indexer
- Settings UI for contracts, networks, API keys, and indexer configuration
- Responsive, real-time interface built with Phoenix LiveView and Tailwind CSS

## Prerequisites

- Elixir `~> 1.17` and Erlang/OTP
- PostgreSQL
- Node.js (for Tailwind and esbuild assets)
- Access to an Envio Hyperindex deployment (or compatible GraphQL endpoint)

## Setup

For a fresh development environment:

```bash
mix setup
```

This installs dependencies, creates and migrates the database, and builds frontend assets.

To run the steps manually:

```bash
mix deps.get
mix ecto.setup
mix assets.setup
mix assets.build
```

## Configuration

Most runtime configuration can be managed through the Settings pages in the UI. The following environment variables are relevant:

| Variable            | Required | Description                                               |
|---------------------|----------|-----------------------------------------------------------|
| `ENVIO_GRAPHQL_URL` | No       | Envio Hyperindex GraphQL endpoint for indexed data       |
| `DATABASE_URL`      | Prod     | PostgreSQL connection URL                                |
| `SECRET_KEY_BASE`   | Prod     | Secret key for signing and encrypting session data       |
| `PHX_HOST`          | Prod     | Hostname used in generated URLs                          |
| `PORT`              | No       | HTTP port for the web server (default: `4000`)           |
| `ETHERSCAN_API_KEY` | No       | API key for contract verification and explorer features  |

`ENVIO_GRAPHQL_URL` can also be configured from the Indexer settings page (`/settings/indexer`); the value is then stored in the database.

## Running

Start the Phoenix server:

```bash
mix phx.server
```

Or with IEx:

```bash
iex -S mix phx.server
```

Visit `http://localhost:4000` in your browser.

Ensure the Envio GraphQL endpoint is configured via `ENVIO_GRAPHQL_URL` or through the Indexer settings page before exploring data.

## Routes

Key routes exposed by the application:

| Path                    | Description                                  |
|-------------------------|----------------------------------------------|
| `/`                     | Dashboard                                   |
| `/transactions`         | Transactions list                           |
| `/transactions/:id`     | Transaction details                         |
| `/resources`            | Resources list                              |
| `/resources/:id`        | Resource details                            |
| `/actions`              | Actions list                                |
| `/actions/:id`          | Action details                              |
| `/compliances`          | Compliance units list                       |
| `/compliances/:id`      | Compliance unit details                     |
| `/logics`               | Logic inputs list                           |
| `/logics/:id`           | Logic input details                         |
| `/commitments`          | Commitment tree roots                       |
| `/nullifiers`           | Nullifiers                                  |
| `/playground`           | GraphQL playground                          |
| `/settings/contracts`   | Managed contract addresses                  |
| `/settings/networks`    | Network configuration                       |
| `/settings/api-keys`    | API keys (e.g. Etherscan)                   |
| `/settings/indexer`     | Envio indexer endpoint configuration        |

## Testing

Run the Elixir test suite:

```bash
mix test
```

For a stricter, pre-commit style check:

```bash
mix precommit
```

## Architecture

- `lib/anoma_explorer/indexer/`: Envio indexer client, configuration, and GraphQL queries
- `lib/anoma_explorer/settings/`: Persistent application settings (contracts, networks, indexer URL, API keys)
- `lib/anoma_explorer_web/live/`: LiveView modules for dashboard, explorer pages, settings, and GraphQL playground
- `assets/`: Frontend assets (Tailwind CSS and JavaScript)
- `indexer/`: TypeScript project defining the Envio Hyperindex indexer (see `indexer/README.md`)

## License

See LICENSE file.
