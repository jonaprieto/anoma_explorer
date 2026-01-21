# Anoma Explorer

A Phoenix/LiveView application for tracking Anoma contract activity across multiple EVM networks using Alchemy APIs.

## Features

- **Activity Feed**: Real-time view of contract logs, transactions, and transfers
- **Analytics Dashboard**: Charts and statistics with filtering by network and time period
- **Multi-Network Support**: Track contracts across Ethereum, Base, Optimism, Arbitrum, Polygon (mainnet and testnets)
- **Background Ingestion**: Oban-powered background jobs for continuous data sync
- **Rate Limiting**: Built-in rate limiter to stay within Alchemy API limits

## Prerequisites

- Elixir 1.17+
- PostgreSQL
- An [Alchemy](https://www.alchemy.com/) API key

## Setup

1. Install dependencies:

```bash
mix deps.get
```

2. Create and migrate the database:

```bash
mix ecto.setup
```

3. Install frontend assets:

```bash
mix assets.setup
```

## Configuration

Set the following environment variables:

| Variable | Required | Description |
|----------|----------|-------------|
| `ALCHEMY_API_KEY` | Yes | Your Alchemy API key |
| `CONTRACT_ADDRESS` | Yes | Contract address to track (e.g., `0x9ED43C229480659bF6B6607C46d7B96c6D760cBB`) |
| `ALCHEMY_NETWORKS` | No | Comma-separated networks (default: `eth-mainnet,eth-sepolia,base-mainnet,base-sepolia`) |
| `MAX_REQ_PER_SECOND` | No | Rate limit for Alchemy API (default: `5`) |
| `POLL_INTERVAL` | No | Seconds between ingestion polls (default: `30`) |

Example:

```bash
export ALCHEMY_API_KEY=your_api_key_here
export CONTRACT_ADDRESS=0x9ED43C229480659bF6B6607C46d7B96c6D760cBB
export ALCHEMY_NETWORKS=eth-mainnet,base-mainnet
```

## Running

Start the Phoenix server:

```bash
mix phx.server
```

Or with IEx:

```bash
iex -S mix phx.server
```

Visit [http://localhost:4000](http://localhost:4000) in your browser.

## Routes

| Path | Description |
|------|-------------|
| `/` | Landing page |
| `/activity` | Activity feed with filtering |
| `/analytics` | Analytics dashboard |

## Testing

Run the test suite:

```bash
mix test
```

Run with coverage:

```bash
mix test --cover
```

## IEx Helpers

The project includes helpful IEx functions in `.iex.exs`:

```elixir
# Show configured contract addresses
H.anoma_addrs()

# Run a single ingestion cycle
H.ingest_once("eth-mainnet")

# Get latest activities
H.latest(10)

# Get current block number
H.block("eth-mainnet")
```

## Architecture

- **Alchemy Client** (`lib/anoma_explorer/alchemy.ex`): HTTP client for Alchemy APIs
- **Sync Module** (`lib/anoma_explorer/ingestion/sync.ex`): Data ingestion with atomic cursor updates
- **Oban Workers** (`lib/anoma_explorer/workers/`): Background job processing
- **LiveView** (`lib/anoma_explorer_web/live/`): Real-time UI components

## License

See LICENSE file.
