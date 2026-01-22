# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     AnomaExplorer.Repo.insert!(%AnomaExplorer.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias AnomaExplorer.Repo
alias AnomaExplorer.Settings.Protocol
alias AnomaExplorer.Settings.ContractAddress
alias AnomaExplorer.Settings.Network

# ============================================
# Helper Functions
# ============================================

upsert_network = fn attrs ->
  case Repo.get_by(Network, name: attrs.name) do
    nil ->
      %Network{}
      |> Network.changeset(attrs)
      |> Repo.insert!()

    network ->
      network
      |> Network.changeset(attrs)
      |> Repo.update!()
  end
end

get_or_create_protocol = fn name, description, github_url ->
  case Repo.get_by(Protocol, name: name) do
    nil ->
      %Protocol{}
      |> Protocol.changeset(%{
        name: name,
        description: description,
        github_url: github_url,
        active: true
      })
      |> Repo.insert!()

    protocol ->
      # Update github_url if it changed
      if protocol.github_url != github_url do
        protocol
        |> Protocol.changeset(%{github_url: github_url})
        |> Repo.update!()
      else
        protocol
      end
  end
end

upsert_address = fn protocol_id, category, version, network, address ->
  attrs = %{
    protocol_id: protocol_id,
    category: category,
    version: version,
    network: network,
    address: String.downcase(address),
    active: true
  }

  %ContractAddress{}
  |> ContractAddress.changeset(attrs)
  |> Repo.insert!(
    on_conflict: {:replace, [:address, :active, :updated_at]},
    conflict_target: [:protocol_id, :category, :version, :network]
  )
end

# ============================================
# Seed Networks
# ============================================

IO.puts("Seeding Networks...")

# Networks matching indexer/config.yaml
# Active status is computed at runtime based on indexer config
networks = [
  %{
    name: "eth-mainnet",
    display_name: "Ethereum",
    chain_id: 1,
    explorer_url: "https://etherscan.io",
    is_testnet: false,
    active: true
  },
  %{
    name: "eth-sepolia",
    display_name: "Sepolia",
    chain_id: 11_155_111,
    explorer_url: "https://sepolia.etherscan.io",
    is_testnet: true,
    active: true
  },
  %{
    name: "arb-mainnet",
    display_name: "Arbitrum One",
    chain_id: 42150,
    explorer_url: "https://arbiscan.io",
    is_testnet: false,
    active: true
  }
]

Enum.each(networks, fn attrs ->
  upsert_network.(attrs)
  IO.puts("  #{attrs.name}: #{attrs.display_name} (chain_id: #{attrs.chain_id})")
end)

IO.puts("")

# ============================================
# Seed Protocol Adapter
# ============================================

IO.puts("Seeding Protocol Adapter...")

protocol_adapter =
  get_or_create_protocol.(
    "Protocol Adapter",
    "Anoma Protocol Adapter for EVM chains",
    "https://github.com/anoma/pa-evm"
  )

IO.puts("  Protocol ID: #{protocol_adapter.id}")

# Contract addresses must match indexer/config.yaml
protocol_adapter_v1 = [
  {"eth-mainnet", "0xdd4f4F0875Da48EF6d8F32ACB890EC81F435Ff3a"},
  {"eth-sepolia", "0xc63336a48D0f60faD70ed027dFB256908bBD5e37"},
  {"arb-mainnet", "0x212f275c6dD4829cd84ABDF767b0Df4A9CB9ef60"}
]

IO.puts("Seeding Protocol Adapter v1.0 addresses...")

Enum.each(protocol_adapter_v1, fn {network, address} ->
  upsert_address.(protocol_adapter.id, "protocol_adapter", "v1.0", network, address)
  IO.puts("  #{network}: #{address}")
end)

# ============================================
# Summary
# ============================================

total_networks = length(networks)
total_addresses = length(protocol_adapter_v1)
IO.puts("")
IO.puts("Done! Seeded:")
IO.puts("  - #{total_networks} networks")
IO.puts("  - 1 protocol (Protocol Adapter)")
IO.puts("  - #{total_addresses} contract addresses")
IO.puts("  - Version: v1.0")
