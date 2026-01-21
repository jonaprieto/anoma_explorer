defmodule AnomaExplorer.ConfigTest do
  use ExUnit.Case, async: true

  alias AnomaExplorer.Config

  describe "validate_contract_address/1" do
    test "accepts valid lowercase address" do
      assert {:ok, "0x" <> rest} =
               Config.validate_contract_address("0x742d35cc6634c0532925a3b844bc9e7595f0ab12")

      assert String.length(rest) == 40
    end

    test "downcases uppercase address" do
      {:ok, addr} = Config.validate_contract_address("0x742D35CC6634C0532925A3B844BC9E7595F0AB12")
      assert addr == "0x742d35cc6634c0532925a3b844bc9e7595f0ab12"
    end

    test "handles mixed case address" do
      {:ok, addr} = Config.validate_contract_address("0x742D35Cc6634c0532925a3B844Bc9e7595F0Ab12")
      assert addr == "0x742d35cc6634c0532925a3b844bc9e7595f0ab12"
    end

    test "rejects address without 0x prefix" do
      assert {:error, _} =
               Config.validate_contract_address("742d35cc6634c0532925a3b844bc9e7595f0ab12")
    end

    test "rejects address with wrong length" do
      assert {:error, _} =
               Config.validate_contract_address("0x742d35cc6634c0532925a3b844bc9e7595f0ab")

      assert {:error, _} =
               Config.validate_contract_address("0x742d35cc6634c0532925a3b844bc9e7595f0ab1234")
    end

    test "rejects address with non-hex characters" do
      assert {:error, _} =
               Config.validate_contract_address("0x742d35cc6634c0532925a3b844bc9e7595f0abzz")
    end

    test "rejects nil" do
      assert {:error, _} = Config.validate_contract_address(nil)
    end

    test "rejects empty string" do
      assert {:error, _} = Config.validate_contract_address("")
    end
  end

  describe "parse_networks/1" do
    test "parses single network" do
      assert {:ok, ["eth-mainnet"]} = Config.parse_networks("eth-mainnet")
    end

    test "parses multiple networks" do
      {:ok, networks} = Config.parse_networks("eth-mainnet,arb-mainnet,polygon-mainnet")
      assert networks == ["eth-mainnet", "arb-mainnet", "polygon-mainnet"]
    end

    test "trims whitespace" do
      {:ok, networks} = Config.parse_networks(" eth-mainnet , arb-mainnet ")
      assert networks == ["eth-mainnet", "arb-mainnet"]
    end

    test "validates known networks" do
      {:ok, networks} =
        Config.parse_networks(
          "eth-mainnet,arb-mainnet,polygon-mainnet,base-mainnet,optimism-mainnet"
        )

      assert length(networks) == 5
    end

    test "rejects unknown network" do
      assert {:error, _} = Config.parse_networks("unknown-network")
    end

    test "rejects empty string" do
      assert {:error, _} = Config.parse_networks("")
    end

    test "rejects nil" do
      assert {:error, _} = Config.parse_networks(nil)
    end
  end

  describe "supported_networks/0" do
    test "returns list of supported networks" do
      networks = Config.supported_networks()
      assert is_list(networks)
      assert "eth-mainnet" in networks
      assert "arb-mainnet" in networks
      assert "polygon-mainnet" in networks
      assert "base-mainnet" in networks
      assert "optimism-mainnet" in networks
    end
  end

  describe "parse_positive_integer/2" do
    test "parses valid integer string" do
      assert {:ok, 100} = Config.parse_positive_integer("100", :page_size)
    end

    test "rejects zero" do
      assert {:error, _} = Config.parse_positive_integer("0", :page_size)
    end

    test "rejects negative" do
      assert {:error, _} = Config.parse_positive_integer("-5", :page_size)
    end

    test "rejects non-numeric" do
      assert {:error, _} = Config.parse_positive_integer("abc", :page_size)
    end

    test "returns default for nil when default provided" do
      assert {:ok, 20} = Config.parse_positive_integer(nil, :poll_interval, 20)
    end
  end

  describe "network_rpc_url/2" do
    test "builds correct URL for eth-mainnet" do
      url = Config.network_rpc_url("eth-mainnet", "test_api_key")
      assert url == "https://eth-mainnet.g.alchemy.com/v2/test_api_key"
    end

    test "builds correct URL for polygon-mainnet" do
      url = Config.network_rpc_url("polygon-mainnet", "test_api_key")
      assert url == "https://polygon-mainnet.g.alchemy.com/v2/test_api_key"
    end

    test "builds correct URL for base-mainnet" do
      url = Config.network_rpc_url("base-mainnet", "test_api_key")
      assert url == "https://base-mainnet.g.alchemy.com/v2/test_api_key"
    end
  end
end
