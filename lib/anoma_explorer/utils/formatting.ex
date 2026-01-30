defmodule AnomaExplorer.Utils.Formatting do
  @moduledoc """
  Common formatting utilities for strings, numbers, timestamps, and blockchain values.

  This module consolidates formatting functions used across the application to
  eliminate duplication and provide a single source of truth for data presentation.
  """

  # ============================================
  # String Truncation
  # ============================================

  @doc """
  Truncates a hash or hex string to show only the last 6 characters.

  This compact format is optimized for mobile displays while still
  allowing identification of different hashes. Full hash is available
  via copy button or tooltip.

  ## Options
    * `:suffix_length` - Characters to show at the end (default: 6)

  ## Examples

      iex> truncate_hash("0x1234567890abcdef1234567890abcdef")
      "...abcdef"

      iex> truncate_hash(nil)
      "-"

      iex> truncate_hash("short")
      "short"
  """
  @spec truncate_hash(String.t() | nil, keyword()) :: String.t()
  def truncate_hash(hash, opts \\ [])
  def truncate_hash(nil, _opts), do: "-"

  def truncate_hash(hash, opts) when is_binary(hash) do
    suffix_length = Keyword.get(opts, :suffix_length, 6)

    if byte_size(hash) > suffix_length do
      "..." <> String.slice(hash, -suffix_length, suffix_length)
    else
      hash
    end
  end

  @doc """
  Truncates a hash with longer display (8 chars suffix).
  Useful for resource IDs and logic references.

  ## Examples

      iex> truncate_hash_long("0x1234567890abcdef1234567890abcdef12345678")
      "...12345678"
  """
  @spec truncate_hash_long(String.t() | nil) :: String.t()
  def truncate_hash_long(hash) do
    truncate_hash(hash, suffix_length: 8)
  end

  @doc """
  Truncates long values (used for displaying large text fields).

  ## Examples

      iex> truncate_value("very long string that exceeds the limit...")
      "very long stri...imit..."

      iex> truncate_value(nil)
      nil
  """
  @spec truncate_value(String.t() | nil, non_neg_integer()) :: String.t() | nil
  def truncate_value(value, max_length \\ 50)
  def truncate_value(nil, _max_length), do: nil

  def truncate_value(val, max_length) when is_binary(val) and byte_size(val) > max_length do
    half = div(max_length - 3, 2)
    String.slice(val, 0, half) <> "..." <> String.slice(val, -half, half)
  end

  def truncate_value(val, _max_length), do: to_string(val)

  # ============================================
  # Number Formatting
  # ============================================

  @doc """
  Formats a number with thousand separators.

  ## Examples

      iex> format_number(1234567)
      "1,234,567"

      iex> format_number(nil)
      "-"
  """
  @spec format_number(integer() | nil) :: String.t()
  def format_number(nil), do: "-"

  def format_number(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  def format_number(n), do: to_string(n)

  # ============================================
  # Timestamp & DateTime Formatting
  # ============================================

  @doc """
  Formats a Unix timestamp to a relative time string.

  ## Examples

      iex> format_timestamp(1704067200)
      "5m ago"

      iex> format_timestamp(nil)
      "-"
  """
  @spec format_timestamp(integer() | nil) :: String.t()
  def format_timestamp(nil), do: "-"

  def format_timestamp(ts) when is_integer(ts) do
    case DateTime.from_unix(ts) do
      {:ok, dt} -> format_relative(dt)
      _ -> "-"
    end
  end

  def format_timestamp(_), do: "-"

  @doc """
  Formats a Unix timestamp to a full datetime string (YYYY-MM-DD HH:MM:SS UTC).

  ## Examples

      iex> format_timestamp_full(1704067200)
      "2024-01-01 00:00:00 UTC"

      iex> format_timestamp_full(nil)
      "-"
  """
  @spec format_timestamp_full(integer() | nil) :: String.t()
  def format_timestamp_full(nil), do: "-"

  def format_timestamp_full(ts) when is_integer(ts) do
    case DateTime.from_unix(ts) do
      {:ok, dt} -> Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
      _ -> "-"
    end
  end

  def format_timestamp_full(_), do: "-"

  @doc """
  Formats a DateTime as time only (HH:MM:SS).

  ## Examples

      iex> format_time(~U[2024-01-01 14:30:45Z])
      "14:30:45"
  """
  @spec format_time(DateTime.t()) :: String.t()
  def format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  @doc """
  Formats a DateTime as relative time ("5s ago", "2h ago", etc).

  ## Examples

      iex> format_relative(DateTime.utc_now())
      "0s ago"
  """
  @spec format_relative(DateTime.t()) :: String.t()
  def format_relative(%DateTime{} = dt) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, dt, :second)

    cond do
      diff < 0 -> "in the future"
      diff < 60 -> "#{diff}s ago"
      diff < 3600 ->
        minutes = div(diff, 60)
        seconds = rem(diff, 60)
        "#{minutes}m #{seconds}s ago"
      diff < 86_400 ->
        hours = div(diff, 3600)
        minutes = div(rem(diff, 3600), 60)
        "#{hours}h #{minutes}m ago"
      true ->
        days = div(diff, 86_400)
        hours = div(rem(diff, 86_400), 3600)
        "#{days}d #{hours}h ago"
    end
  end

  # ============================================
  # Cryptocurrency Value Formatting
  # ============================================

  @wei_per_gwei 1_000_000_000
  @wei_per_eth 1_000_000_000_000_000_000

  @doc """
  Formats Wei value to Gwei (for gas price display).

  ## Examples

      iex> format_gwei(1_000_000_000)
      "1.0 Gwei"

      iex> format_gwei(nil)
      "-"
  """
  @spec format_gwei(integer() | String.t() | nil) :: String.t()
  def format_gwei(nil), do: "-"

  def format_gwei(wei) when is_integer(wei) do
    gwei = wei / @wei_per_gwei
    "#{Float.round(gwei, 2)} Gwei"
  end

  def format_gwei(wei) when is_binary(wei) do
    case Integer.parse(wei) do
      {n, _} -> format_gwei(n)
      :error -> "-"
    end
  end

  def format_gwei(_), do: "-"

  @doc """
  Formats Wei value to ETH (for value display).

  ## Examples

      iex> format_eth(1_000_000_000_000_000_000)
      "1.0 ETH"

      iex> format_eth(nil)
      "-"
  """
  @spec format_eth(integer() | String.t() | nil) :: String.t()
  def format_eth(nil), do: "-"

  def format_eth(wei) when is_integer(wei) do
    eth = wei / @wei_per_eth
    "#{Float.round(eth, 6)} ETH"
  end

  def format_eth(wei) when is_binary(wei) do
    case Integer.parse(wei) do
      {n, _} -> format_eth(n)
      :error -> "-"
    end
  end

  def format_eth(_), do: "-"

  @doc """
  Calculates and formats transaction fee (gasUsed * gasPrice) in ETH.

  ## Examples

      iex> format_tx_fee(21000, 50_000_000_000)
      "0.00105 ETH"
  """
  @spec format_tx_fee(integer() | String.t() | nil, integer() | String.t() | nil) :: String.t()
  def format_tx_fee(gas_used, gas_price) when is_integer(gas_used) and is_integer(gas_price) do
    fee_wei = gas_used * gas_price
    format_eth(fee_wei)
  end

  def format_tx_fee(gas_used, gas_price) when is_binary(gas_used) and is_binary(gas_price) do
    with {gu, _} <- Integer.parse(gas_used),
         {gp, _} <- Integer.parse(gas_price) do
      format_tx_fee(gu, gp)
    else
      _ -> "-"
    end
  end

  def format_tx_fee(_, _), do: "-"

  # ============================================
  # Boolean & Status Formatting
  # ============================================

  @doc """
  Formats a boolean value as "Yes" or "No".

  ## Examples

      iex> format_bool(true)
      "Yes"

      iex> format_bool(false)
      "No"

      iex> format_bool(nil)
      nil
  """
  @spec format_bool(boolean() | nil) :: String.t() | nil
  def format_bool(nil), do: nil
  def format_bool(true), do: "Yes"
  def format_bool(false), do: "No"

  @doc """
  Formats error tuples into human-readable messages.

  ## Examples

      iex> format_error(:not_configured)
      "Indexer endpoint not configured"

      iex> format_error({:http_error, 500, "Server Error"})
      "HTTP error: 500"
  """
  @spec format_error(term()) :: String.t()
  def format_error(:not_configured), do: "Indexer endpoint not configured"
  def format_error({:connection_error, _}), do: "Failed to connect to indexer"
  def format_error({:http_error, status, _}), do: "HTTP error: #{status}"
  def format_error({:graphql_error, errors}), do: "GraphQL error: #{inspect(errors)}"
  def format_error(reason), do: "Error: #{inspect(reason)}"

  # ============================================
  # String Escaping
  # ============================================

  @doc """
  Escapes a string for safe inclusion in GraphQL queries.

  Handles backslashes, quotes, newlines, tabs, and SQL LIKE wildcards.

  ## Examples

      iex> escape_string("hello\\nworld")
      "hello\\\\nworld"

      iex> escape_string("test%query")
      "test\\\\%query"
  """
  @spec escape_string(String.t() | term()) :: String.t()
  def escape_string(str) when is_binary(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  def escape_string(other), do: escape_string(to_string(other))
end
