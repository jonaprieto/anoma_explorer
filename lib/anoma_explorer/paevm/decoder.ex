defmodule AnomaExplorer.Paevm.Decoder do
  @moduledoc """
  Decodes raw Ethereum logs into PA-EVM event structs.

  Handles ABI decoding for:
  - TransactionExecuted(bytes32[] tags, bytes32[] logicRefs)
  - ActionExecuted(bytes32 actionTreeRoot, uint256 actionTagCount)
  - ResourcePayload(bytes32 indexed tag, uint256 index, bytes blob)
  - DiscoveryPayload(bytes32 indexed tag, uint256 index, bytes blob)
  - ExternalPayload(bytes32 indexed tag, uint256 index, bytes blob)
  - ApplicationPayload(bytes32 indexed tag, uint256 index, bytes blob)
  - CommitmentTreeRootAdded(bytes32 root)
  - ForwarderCallExecuted(address indexed untrustedForwarder, bytes input, bytes output)
  """

  alias AnomaExplorer.Paevm.ABI

  @doc """
  Decodes a raw log into a structured event.

  Returns a tuple of {event_type, decoded_data} or {:unknown, raw_log}.
  """
  def decode_log(log) when is_map(log) do
    topic0 = get_topic(log, 0)
    event_type = ABI.identify_event(topic0)

    case event_type do
      :transaction_executed -> decode_transaction_executed(log)
      :action_executed -> decode_action_executed(log)
      :resource_payload -> decode_payload(log, "resource")
      :discovery_payload -> decode_payload(log, "discovery")
      :external_payload -> decode_payload(log, "external")
      :application_payload -> decode_payload(log, "application")
      :commitment_tree_root_added -> decode_commitment_tree_root(log)
      :forwarder_call_executed -> decode_forwarder_call(log)
      :unknown -> {:unknown, log}
    end
  end

  def decode_log(_), do: {:error, :invalid_log}

  @doc """
  Decodes TransactionExecuted(bytes32[] tags, bytes32[] logicRefs) event.

  Both arrays are non-indexed and encoded in the data field.
  """
  def decode_transaction_executed(log) do
    data = get_data(log)

    case decode_two_bytes32_arrays(data) do
      {:ok, tags, logic_refs} ->
        {:transaction_executed,
         %{
           tags: tags,
           logic_refs: logic_refs,
           tx_hash: get_field(log, "transactionHash"),
           block_number: parse_hex_int(get_field(log, "blockNumber")),
           log_index: parse_hex_int(get_field(log, "logIndex")),
           raw: log
         }}

      {:error, reason} ->
        {:error, {:decode_failed, :transaction_executed, reason}}
    end
  end

  @doc """
  Decodes ActionExecuted(bytes32 actionTreeRoot, uint256 actionTagCount) event.

  Both parameters are non-indexed and encoded in the data field.
  """
  def decode_action_executed(log) do
    data = get_data(log)

    case decode_bytes32_and_uint256(data) do
      {:ok, action_tree_root, action_tag_count} ->
        {:action_executed,
         %{
           action_tree_root: action_tree_root,
           action_tag_count: action_tag_count,
           tx_hash: get_field(log, "transactionHash"),
           block_number: parse_hex_int(get_field(log, "blockNumber")),
           log_index: parse_hex_int(get_field(log, "logIndex")),
           raw: log
         }}

      {:error, reason} ->
        {:error, {:decode_failed, :action_executed, reason}}
    end
  end

  @doc """
  Decodes payload events (*Payload(bytes32 indexed tag, uint256 index, bytes blob)).

  The tag is indexed (in topics[1]), index and blob are in data.
  """
  def decode_payload(log, payload_type) do
    tag = get_topic(log, 1)
    data = get_data(log)

    case decode_uint256_and_bytes(data) do
      {:ok, index, blob} ->
        {:payload,
         %{
           payload_type: payload_type,
           tag: tag,
           index: index,
           blob: blob,
           tx_hash: get_field(log, "transactionHash"),
           block_number: parse_hex_int(get_field(log, "blockNumber")),
           log_index: parse_hex_int(get_field(log, "logIndex")),
           raw: log
         }}

      {:error, reason} ->
        {:error, {:decode_failed, :payload, reason}}
    end
  end

  @doc """
  Decodes CommitmentTreeRootAdded(bytes32 root) event.

  The root is non-indexed and encoded in the data field.
  """
  def decode_commitment_tree_root(log) do
    data = get_data(log)

    case decode_bytes32(data) do
      {:ok, root} ->
        {:commitment_tree_root_added,
         %{
           root: root,
           tx_hash: get_field(log, "transactionHash"),
           block_number: parse_hex_int(get_field(log, "blockNumber")),
           log_index: parse_hex_int(get_field(log, "logIndex")),
           raw: log
         }}

      {:error, reason} ->
        {:error, {:decode_failed, :commitment_tree_root_added, reason}}
    end
  end

  @doc """
  Decodes ForwarderCallExecuted(address indexed untrustedForwarder, bytes input, bytes output) event.

  The forwarder address is indexed (in topics[1]), input and output are in data.
  """
  def decode_forwarder_call(log) do
    forwarder_topic = get_topic(log, 1)
    forwarder = decode_address_from_topic(forwarder_topic)
    data = get_data(log)

    case decode_two_bytes(data) do
      {:ok, input, output} ->
        {:forwarder_call_executed,
         %{
           forwarder_address: forwarder,
           input: input,
           output: output,
           tx_hash: get_field(log, "transactionHash"),
           block_number: parse_hex_int(get_field(log, "blockNumber")),
           log_index: parse_hex_int(get_field(log, "logIndex")),
           raw: log
         }}

      {:error, reason} ->
        {:error, {:decode_failed, :forwarder_call_executed, reason}}
    end
  end

  # ============================================
  # ABI Decoding Helpers
  # ============================================

  @doc """
  Decodes two bytes32[] arrays from ABI-encoded data.
  Standard ABI encoding: offset1 (32 bytes) | offset2 (32 bytes) | array1 | array2
  """
  def decode_two_bytes32_arrays(data) when is_binary(data) and byte_size(data) >= 64 do
    <<offset1::unsigned-256, offset2::unsigned-256, _rest::binary>> = data

    with {:ok, tags} <- decode_bytes32_array_at_offset(data, offset1),
         {:ok, logic_refs} <- decode_bytes32_array_at_offset(data, offset2) do
      {:ok, tags, logic_refs}
    end
  end

  def decode_two_bytes32_arrays(_), do: {:error, :insufficient_data}

  @doc """
  Decodes a bytes32 array at a given offset.
  """
  def decode_bytes32_array_at_offset(data, offset) when byte_size(data) > offset do
    rest = binary_part(data, offset, byte_size(data) - offset)

    case rest do
      <<length::unsigned-256, elements::binary>> when byte_size(elements) >= length * 32 ->
        items =
          for i <- 0..(length - 1) do
            element = binary_part(elements, i * 32, 32)
            encode_hex(element)
          end

        {:ok, items}

      _ ->
        {:error, :malformed_array}
    end
  end

  def decode_bytes32_array_at_offset(_, _), do: {:error, :invalid_offset}

  @doc """
  Decodes bytes32 followed by uint256 from data.
  """
  def decode_bytes32_and_uint256(data) when byte_size(data) >= 64 do
    <<bytes32::binary-size(32), uint256::unsigned-256, _rest::binary>> = data
    {:ok, encode_hex(bytes32), uint256}
  end

  def decode_bytes32_and_uint256(_), do: {:error, :insufficient_data}

  @doc """
  Decodes a single bytes32 from data.
  """
  def decode_bytes32(data) when byte_size(data) >= 32 do
    <<bytes32::binary-size(32), _rest::binary>> = data
    {:ok, encode_hex(bytes32)}
  end

  def decode_bytes32(_), do: {:error, :insufficient_data}

  @doc """
  Decodes uint256 followed by bytes from ABI-encoded data.
  ABI encoding: uint256 | offset_to_bytes | ... | length | bytes_content
  """
  def decode_uint256_and_bytes(data) when byte_size(data) >= 64 do
    <<index::unsigned-256, offset::unsigned-256, _rest::binary>> = data

    case decode_bytes_at_offset(data, offset) do
      {:ok, blob} -> {:ok, index, blob}
      error -> error
    end
  end

  def decode_uint256_and_bytes(_), do: {:error, :insufficient_data}

  @doc """
  Decodes two bytes parameters from ABI-encoded data.
  ABI encoding: offset1 | offset2 | ... | length1 | bytes1 | length2 | bytes2
  """
  def decode_two_bytes(data) when byte_size(data) >= 64 do
    <<offset1::unsigned-256, offset2::unsigned-256, _rest::binary>> = data

    with {:ok, bytes1} <- decode_bytes_at_offset(data, offset1),
         {:ok, bytes2} <- decode_bytes_at_offset(data, offset2) do
      {:ok, bytes1, bytes2}
    end
  end

  def decode_two_bytes(_), do: {:error, :insufficient_data}

  @doc """
  Decodes a bytes parameter at a given offset.
  """
  def decode_bytes_at_offset(data, offset) when byte_size(data) > offset + 32 do
    rest = binary_part(data, offset, byte_size(data) - offset)

    case rest do
      <<length::unsigned-256, content::binary>> when byte_size(content) >= length ->
        {:ok, binary_part(content, 0, length)}

      _ ->
        {:error, :malformed_bytes}
    end
  end

  def decode_bytes_at_offset(_, _), do: {:error, :invalid_offset}

  @doc """
  Decodes an address from a topic (32 bytes, right-aligned).
  """
  def decode_address_from_topic(nil), do: nil

  def decode_address_from_topic(topic) do
    case decode_hex(topic) do
      {:ok, bytes} when byte_size(bytes) == 32 ->
        # Address is 20 bytes, right-aligned in 32-byte topic
        <<_padding::binary-size(12), address::binary-size(20)>> = bytes
        encode_hex(address)

      _ ->
        topic
    end
  end

  # ============================================
  # Hex Encoding/Decoding Helpers
  # ============================================

  @doc """
  Decodes a hex string (with or without 0x prefix) to binary.
  """
  def decode_hex("0x" <> hex), do: decode_hex(hex)

  def decode_hex(hex) when is_binary(hex) do
    case Base.decode16(hex, case: :mixed) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, :invalid_hex}
    end
  end

  def decode_hex(_), do: {:error, :invalid_input}

  @doc """
  Encodes binary to hex string with 0x prefix.
  """
  def encode_hex(binary) when is_binary(binary) do
    "0x" <> Base.encode16(binary, case: :lower)
  end

  def encode_hex(_), do: nil

  @doc """
  Parses a hex string to integer.
  """
  def parse_hex_int(nil), do: nil
  def parse_hex_int("0x" <> hex), do: parse_hex_int(hex)

  def parse_hex_int(hex) when is_binary(hex) do
    case Integer.parse(hex, 16) do
      {int, ""} -> int
      _ -> nil
    end
  end

  def parse_hex_int(int) when is_integer(int), do: int
  def parse_hex_int(_), do: nil

  # ============================================
  # Log Field Accessors
  # ============================================

  defp get_field(log, field) when is_map(log) do
    # Handle both string and atom keys
    Map.get(log, field) || Map.get(log, String.to_atom(field))
  end

  defp get_topic(log, index) do
    topics = get_field(log, "topics") || []
    Enum.at(topics, index)
  end

  defp get_data(log) do
    data_hex = get_field(log, "data") || "0x"

    case decode_hex(data_hex) do
      {:ok, bytes} -> bytes
      _ -> <<>>
    end
  end
end
