defmodule AnomaExplorer.Ingestion do
  @moduledoc """
  Context module for managing ingestion state.

  Tracks the progress of data ingestion per network/contract combination.
  """
  import Ecto.Query

  alias AnomaExplorer.Repo
  alias AnomaExplorer.Ingestion.IngestionState

  @doc """
  Gets or creates an ingestion state record for a network/contract pair.
  """
  @spec get_or_create_state(String.t(), String.t()) ::
          {:ok, IngestionState.t()} | {:error, Ecto.Changeset.t()}
  def get_or_create_state(network, contract_address) do
    attrs = %{network: network, contract_address: contract_address}

    %IngestionState{}
    |> IngestionState.changeset(attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:network, :contract_address],
      returning: true
    )
    |> case do
      {:ok, %IngestionState{id: nil}} ->
        # Conflict occurred, fetch existing
        {:ok, get_state(network, contract_address)}

      {:ok, state} ->
        {:ok, state}

      error ->
        error
    end
  end

  @doc """
  Gets an ingestion state record for a network/contract pair.

  Returns nil if not found.
  """
  @spec get_state(String.t(), String.t()) :: IngestionState.t() | nil
  def get_state(network, contract_address) do
    IngestionState
    |> where([s], s.network == ^network and s.contract_address == ^contract_address)
    |> Repo.one()
  end

  @doc """
  Updates an ingestion state record.
  """
  @spec update_state(IngestionState.t(), map()) ::
          {:ok, IngestionState.t()} | {:error, Ecto.Changeset.t()}
  def update_state(state, attrs) do
    state
    |> IngestionState.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Lists all ingestion states.
  """
  @spec list_states() :: [IngestionState.t()]
  def list_states do
    Repo.all(IngestionState)
  end

  @doc """
  Lists ingestion states for a specific contract address across all networks.
  """
  @spec list_states_for_contract(String.t()) :: [IngestionState.t()]
  def list_states_for_contract(contract_address) do
    IngestionState
    |> where([s], s.contract_address == ^contract_address)
    |> Repo.all()
  end
end
