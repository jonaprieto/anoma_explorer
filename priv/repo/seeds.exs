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

# ============================================
# Helper Functions
# ============================================

get_or_create_protocol = fn name, description, github_url ->
  case Repo.get_by(Protocol, name: name) do
    nil ->
      %Protocol{}
      |> Protocol.changeset(%{name: name, description: description, github_url: github_url, active: true})
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
# Seed Protocol Adapter
# ============================================

IO.puts("Seeding Protocol Adapter...")
protocol_adapter = get_or_create_protocol.(
  "Protocol Adapter",
  "Anoma Protocol Adapter for EVM chains",
  "https://github.com/anoma/pa-evm"
)
IO.puts("  Protocol ID: #{protocol_adapter.id}")

protocol_adapter_v1 = [
  {"eth-sepolia", "0xc63336a48D0f60faD70ed027dFB256908bBD5e37"},
  {"eth-mainnet", "0xdd4f4F0875Da48EF6d8F32ACB890EC81F435Ff3a"},
  {"base-sepolia", "0x212f275c6dD4829cd84ABDF767b0Df4A9CB9ef60"},
  {"base-mainnet", "0x212f275c6dD4829cd84ABDF767b0Df4A9CB9ef60"},
  {"optimism-mainnet", "0x212f275c6dD4829cd84ABDF767b0Df4A9CB9ef60"},
  {"arb-mainnet", "0x212f275c6dD4829cd84ABDF767b0Df4A9CB9ef60"}
]

IO.puts("Seeding Protocol Adapter v1.0 addresses...")

Enum.each(protocol_adapter_v1, fn {network, address} ->
  upsert_address.(protocol_adapter.id, "protocol_adapter", "v1.0", network, address)
  IO.puts("  #{network}: #{address}")
end)

# ============================================
# Seed AnomaPay ERC20 Forwarder
# ============================================

IO.puts("Seeding AnomaPay ERC20 Forwarder...")
erc20_forwarder = get_or_create_protocol.(
  "AnomaPay ERC20 Forwarder",
  "ERC20 token forwarder for AnomaPay",
  "https://github.com/anoma/anomapay-erc20-forwarder"
)
IO.puts("  Protocol ID: #{erc20_forwarder.id}")

erc20_forwarder_v1 = [
  {"eth-sepolia", "0xa04942494174eD85A11416E716262eC0AE0a065d"},
  {"eth-mainnet", "0x0D38C332135f9f0de4dcc4a6F9c918b72e2A1Df3"},
  {"base-sepolia", "0xA73Ce304460F17C3530b58BA95bCD3B89Bd38D69"},
  {"base-mainnet", "0xA73Ce304460F17C3530b58BA95bCD3B89Bd38D69"},
  {"optimism-mainnet", "0xA73Ce304460F17C3530b58BA95bCD3B89Bd38D69"},
  {"arb-mainnet", "0xA73Ce304460F17C3530b58BA95bCD3B89Bd38D69"}
]

IO.puts("Seeding ERC20 Forwarder v1.0 addresses...")

Enum.each(erc20_forwarder_v1, fn {network, address} ->
  upsert_address.(erc20_forwarder.id, "erc20_forwarder", "v1.0", network, address)
  IO.puts("  #{network}: #{address}")
end)

# ============================================
# Summary
# ============================================

total_addresses = length(protocol_adapter_v1) + length(erc20_forwarder_v1)
IO.puts("")
IO.puts("Done! Seeded:")
IO.puts("  - 2 protocols (Protocol Adapter, AnomaPay ERC20 Forwarder)")
IO.puts("  - #{total_addresses} contract addresses")
IO.puts("  - Version: v1.0")
