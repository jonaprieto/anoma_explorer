defmodule AnomaExplorer.Paevm.Analytics do
  @moduledoc """
  Analytics queries for PA-EVM transaction data.

  Provides aggregated statistics, time-series data, and metrics
  for the PA-EVM dashboard.
  """

  import Ecto.Query

  alias AnomaExplorer.Paevm.{Transaction, Action, ComplianceUnit, Resource, Payload}
  alias AnomaExplorer.Repo

  @doc """
  Returns summary statistics for the PA-EVM dashboard.

  ## Options
    * `:days` - Number of days to include (default: 7)
    * `:network` - Filter by specific network
    * `:contract_address` - Filter by specific contract
  """
  @spec summary_stats(keyword()) :: map()
  def summary_stats(opts \\ []) do
    days = Keyword.get(opts, :days, 7)
    network = Keyword.get(opts, :network)
    contract_address = Keyword.get(opts, :contract_address)

    start_date = Date.add(Date.utc_today(), -(days - 1))

    base_query =
      Transaction
      |> where([t], fragment("DATE(?)", t.inserted_at) >= ^start_date)
      |> maybe_filter_network(network)
      |> maybe_filter_contract(contract_address)

    total_transactions = Repo.aggregate(base_query, :count)
    total_actions = count_actions(start_date, network, contract_address)
    total_compliance_units = count_compliance_units(start_date, network, contract_address)
    total_resources = count_resources(start_date, network, contract_address)
    unique_logic_refs = count_unique_logic_refs(start_date, network, contract_address)

    total_tags =
      base_query
      |> select([t], sum(t.tag_count))
      |> Repo.one() || 0

    avg_actions_per_tx =
      if total_transactions > 0 do
        Float.round(total_actions / total_transactions, 2)
      else
        0.0
      end

    %{
      total_transactions: total_transactions,
      total_actions: total_actions,
      total_compliance_units: total_compliance_units,
      total_resources: total_resources,
      total_tags: total_tags,
      unique_logic_refs: unique_logic_refs,
      avg_actions_per_tx: avg_actions_per_tx,
      days: days
    }
  end

  @doc """
  Returns daily transaction counts for the specified number of days.

  ## Options
    * `:days` - Number of days to include (default: 30)
    * `:network` - Filter by specific network
    * `:contract_address` - Filter by specific contract
  """
  @spec daily_transaction_counts(keyword()) :: [%{date: Date.t(), count: integer()}]
  def daily_transaction_counts(opts \\ []) do
    days = Keyword.get(opts, :days, 30)
    network = Keyword.get(opts, :network)
    contract_address = Keyword.get(opts, :contract_address)

    end_date = Date.utc_today()
    start_date = Date.add(end_date, -(days - 1))
    date_range = Date.range(start_date, end_date)

    query =
      Transaction
      |> where([t], fragment("DATE(?)", t.inserted_at) >= ^start_date)
      |> where([t], fragment("DATE(?)", t.inserted_at) <= ^end_date)
      |> maybe_filter_network(network)
      |> maybe_filter_contract(contract_address)
      |> group_by([t], fragment("DATE(?)", t.inserted_at))
      |> select([t], {fragment("DATE(?)", t.inserted_at), count(t.id)})

    counts_map =
      query
      |> Repo.all()
      |> Map.new()

    Enum.map(date_range, fn date ->
      %{date: date, count: Map.get(counts_map, date, 0)}
    end)
  end

  @doc """
  Returns logic reference usage statistics.

  ## Options
    * `:limit` - Max results per list (default: 10)
    * `:days` - Number of days to include (default: 30)
  """
  @spec logic_ref_stats(keyword()) :: %{
          top_consumed_logic_refs: [map()],
          top_created_logic_refs: [map()]
        }
  def logic_ref_stats(opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    days = Keyword.get(opts, :days, 30)

    start_date = Date.add(Date.utc_today(), -(days - 1))

    consumed_query =
      from cu in ComplianceUnit,
        join: a in assoc(cu, :action),
        join: t in assoc(a, :transaction),
        where: fragment("DATE(?)", t.inserted_at) >= ^start_date,
        group_by: cu.consumed_logic_ref,
        select: %{logic_ref: cu.consumed_logic_ref, count: count(cu.id)},
        order_by: [desc: count(cu.id)],
        limit: ^limit

    created_query =
      from cu in ComplianceUnit,
        join: a in assoc(cu, :action),
        join: t in assoc(a, :transaction),
        where: fragment("DATE(?)", t.inserted_at) >= ^start_date,
        group_by: cu.created_logic_ref,
        select: %{logic_ref: cu.created_logic_ref, count: count(cu.id)},
        order_by: [desc: count(cu.id)],
        limit: ^limit

    %{
      top_consumed_logic_refs: Repo.all(consumed_query),
      top_created_logic_refs: Repo.all(created_query)
    }
  end

  @doc """
  Returns payload type distribution.

  ## Options
    * `:days` - Number of days to include (default: 30)
  """
  @spec payload_distribution(keyword()) :: %{String.t() => integer()}
  def payload_distribution(opts \\ []) do
    days = Keyword.get(opts, :days, 30)
    start_date = Date.add(Date.utc_today(), -(days - 1))

    from(p in Payload,
      join: t in assoc(p, :transaction),
      where: fragment("DATE(?)", t.inserted_at) >= ^start_date,
      group_by: p.payload_type,
      select: {p.payload_type, count(p.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Returns resource statistics.

  ## Options
    * `:days` - Number of days to include (default: 30)
  """
  @spec resource_stats(keyword()) :: map()
  def resource_stats(opts \\ []) do
    days = Keyword.get(opts, :days, 30)
    start_date = Date.add(Date.utc_today(), -(days - 1))

    base_query =
      from r in Resource,
        where: fragment("DATE(?)", r.inserted_at) >= ^start_date

    total = Repo.aggregate(base_query, :count)

    by_type =
      from(r in Resource,
        where: fragment("DATE(?)", r.inserted_at) >= ^start_date,
        group_by: r.resource_type,
        select: {r.resource_type, count(r.id)}
      )
      |> Repo.all()
      |> Map.new()

    ephemeral_count =
      from(r in Resource,
        where: fragment("DATE(?)", r.inserted_at) >= ^start_date,
        where: r.ephemeral == true
      )
      |> Repo.aggregate(:count)

    %{
      total: total,
      by_type: by_type,
      ephemeral_count: ephemeral_count,
      persistent_count: total - ephemeral_count
    }
  end

  @doc """
  Returns transactions grouped by network.

  ## Options
    * `:days` - Number of days to include (default: 7)
  """
  @spec transactions_by_network(keyword()) :: %{String.t() => integer()}
  def transactions_by_network(opts \\ []) do
    days = Keyword.get(opts, :days, 7)
    start_date = Date.add(Date.utc_today(), -(days - 1))

    from(t in Transaction,
      where: fragment("DATE(?)", t.inserted_at) >= ^start_date,
      group_by: t.network,
      select: {t.network, count(t.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp count_actions(start_date, network, contract_address) do
    from(a in Action,
      join: t in assoc(a, :transaction),
      where: fragment("DATE(?)", t.inserted_at) >= ^start_date
    )
    |> maybe_filter_network_via_tx(network)
    |> maybe_filter_contract_via_tx(contract_address)
    |> Repo.aggregate(:count)
  end

  defp count_compliance_units(start_date, network, contract_address) do
    from(cu in ComplianceUnit,
      join: a in assoc(cu, :action),
      join: t in assoc(a, :transaction),
      where: fragment("DATE(?)", t.inserted_at) >= ^start_date
    )
    |> maybe_filter_network_via_tx(network)
    |> maybe_filter_contract_via_tx(contract_address)
    |> Repo.aggregate(:count)
  end

  defp count_resources(start_date, _network, _contract_address) do
    from(r in Resource,
      where: fragment("DATE(?)", r.inserted_at) >= ^start_date
    )
    |> Repo.aggregate(:count)
  end

  defp count_unique_logic_refs(start_date, network, contract_address) do
    consumed_refs =
      from(cu in ComplianceUnit,
        join: a in assoc(cu, :action),
        join: t in assoc(a, :transaction),
        where: fragment("DATE(?)", t.inserted_at) >= ^start_date,
        select: cu.consumed_logic_ref,
        distinct: true
      )
      |> maybe_filter_network_via_tx(network)
      |> maybe_filter_contract_via_tx(contract_address)
      |> Repo.all()

    created_refs =
      from(cu in ComplianceUnit,
        join: a in assoc(cu, :action),
        join: t in assoc(a, :transaction),
        where: fragment("DATE(?)", t.inserted_at) >= ^start_date,
        select: cu.created_logic_ref,
        distinct: true
      )
      |> maybe_filter_network_via_tx(network)
      |> maybe_filter_contract_via_tx(contract_address)
      |> Repo.all()

    (consumed_refs ++ created_refs)
    |> Enum.uniq()
    |> length()
  end

  defp maybe_filter_network(query, nil), do: query
  defp maybe_filter_network(query, network), do: where(query, [t], t.network == ^network)

  defp maybe_filter_contract(query, nil), do: query

  defp maybe_filter_contract(query, addr),
    do: where(query, [t], t.contract_address == ^addr)

  defp maybe_filter_network_via_tx(query, nil), do: query

  defp maybe_filter_network_via_tx(query, network) do
    where(query, [..., t], t.network == ^network)
  end

  defp maybe_filter_contract_via_tx(query, nil), do: query

  defp maybe_filter_contract_via_tx(query, addr) do
    where(query, [..., t], t.contract_address == ^addr)
  end
end
