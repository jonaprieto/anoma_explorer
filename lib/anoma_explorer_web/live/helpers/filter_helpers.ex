defmodule AnomaExplorerWeb.Live.Helpers.FilterHelpers do
  @moduledoc """
  Shared filter helper functions for LiveView list views.

  These functions are used across multiple LiveView modules for building
  filter options and counting active filters.
  """

  @doc """
  Adds a string filter to the options keyword list if the value is non-empty.

  ## Examples

      iex> maybe_add_filter([], :name, "test")
      [name: "test"]

      iex> maybe_add_filter([], :name, "")
      []

      iex> maybe_add_filter([], :name, nil)
      []
  """
  @spec maybe_add_filter(keyword(), atom(), String.t() | nil) :: keyword()
  def maybe_add_filter(opts, _key, nil), do: opts
  def maybe_add_filter(opts, _key, ""), do: opts
  def maybe_add_filter(opts, key, value), do: Keyword.put(opts, key, value)

  @doc """
  Adds an integer filter to the options keyword list if the value is non-empty.
  Parses string values to integers.

  ## Examples

      iex> maybe_add_int_filter([], :block, "123")
      [block: 123]

      iex> maybe_add_int_filter([], :block, 456)
      [block: 456]

      iex> maybe_add_int_filter([], :block, "")
      []

      iex> maybe_add_int_filter([], :block, "invalid")
      []
  """
  @spec maybe_add_int_filter(keyword(), atom(), String.t() | integer() | nil) :: keyword()
  def maybe_add_int_filter(opts, _key, nil), do: opts
  def maybe_add_int_filter(opts, _key, ""), do: opts

  def maybe_add_int_filter(opts, key, value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> Keyword.put(opts, key, int)
      :error -> opts
    end
  end

  def maybe_add_int_filter(opts, key, value) when is_integer(value) do
    Keyword.put(opts, key, value)
  end

  @doc """
  Adds a boolean filter to the options keyword list if the value is non-empty.
  Parses "true"/"false" string values to booleans.

  ## Examples

      iex> maybe_add_bool_filter([], :active, "true")
      [active: true]

      iex> maybe_add_bool_filter([], :active, "false")
      [active: false]

      iex> maybe_add_bool_filter([], :active, "")
      []

      iex> maybe_add_bool_filter([], :active, "other")
      []
  """
  @spec maybe_add_bool_filter(keyword(), atom(), String.t() | nil) :: keyword()
  def maybe_add_bool_filter(opts, _key, nil), do: opts
  def maybe_add_bool_filter(opts, _key, ""), do: opts
  def maybe_add_bool_filter(opts, key, "true"), do: Keyword.put(opts, key, true)
  def maybe_add_bool_filter(opts, key, "false"), do: Keyword.put(opts, key, false)
  def maybe_add_bool_filter(opts, _key, _), do: opts

  @doc """
  Counts the number of active (non-empty) filters in a filter map.

  ## Options

    * `:exclude` - A list of keys to exclude from the count

  ## Examples

      iex> active_filter_count(%{"name" => "test", "age" => ""})
      1

      iex> active_filter_count(%{"name" => "test", "type" => "all"}, exclude: ["type"])
      1
  """
  @spec active_filter_count(map(), keyword()) :: non_neg_integer()
  def active_filter_count(filters, opts \\ []) do
    exclude_keys = Keyword.get(opts, :exclude, [])

    filters
    |> Enum.reject(fn {k, _v} -> k in exclude_keys end)
    |> Enum.count(fn {_k, v} -> v != "" and not is_nil(v) end)
  end
end
