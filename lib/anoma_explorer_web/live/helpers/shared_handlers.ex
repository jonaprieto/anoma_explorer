defmodule AnomaExplorerWeb.Live.Helpers.SharedHandlers do
  @moduledoc """
  Shared event handler implementations for LiveView modules.

  This module provides helper functions that event handlers can delegate to,
  reducing code duplication across list views.

  ## Usage

      alias AnomaExplorerWeb.Live.Helpers.SharedHandlers

      @impl true
      def handle_event("show_chain_info", %{"chain-id" => chain_id}, socket) do
        {:noreply, SharedHandlers.handle_show_chain_info(socket, chain_id)}
      end
  """

  alias AnomaExplorer.Indexer.Networks

  @doc """
  Handles showing chain information in a modal.

  Expects the socket to have a `:selected_chain` assign.
  """
  @spec handle_show_chain_info(Phoenix.LiveView.Socket.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  def handle_show_chain_info(socket, chain_id_string) do
    chain_id = String.to_integer(chain_id_string)
    Phoenix.Component.assign(socket, :selected_chain, Networks.chain_info(chain_id))
  end

  @doc """
  Handles closing the chain information modal.

  Expects the socket to have a `:selected_chain` assign.
  """
  @spec handle_close_chain_modal(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def handle_close_chain_modal(socket) do
    Phoenix.Component.assign(socket, :selected_chain, nil)
  end

  @doc """
  Handles global search by navigating to the transactions page with a search query.

  Returns `{:navigate, path}` if query is non-empty, or `:noop` if empty.
  """
  @spec handle_global_search(String.t()) :: {:navigate, String.t()} | :noop
  def handle_global_search(query) do
    query = String.trim(query)

    if query != "" do
      {:navigate, "/transactions?search=#{URI.encode_www_form(query)}"}
    else
      :noop
    end
  end

  @doc """
  Handles showing resources in a modal.

  Expects the socket to have a `:selected_resources` assign.
  """
  @spec handle_show_resources(Phoenix.LiveView.Socket.t(), String.t(), String.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  def handle_show_resources(socket, tx_id, tags_json, logic_refs_json) do
    tags = Jason.decode!(tags_json)
    logic_refs = Jason.decode!(logic_refs_json)

    Phoenix.Component.assign(socket, :selected_resources, %{
      tx_id: tx_id,
      tags: tags,
      logic_refs: logic_refs
    })
  end

  @doc """
  Handles closing the resources modal.

  Expects the socket to have a `:selected_resources` assign.
  """
  @spec handle_close_resources_modal(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def handle_close_resources_modal(socket) do
    Phoenix.Component.assign(socket, :selected_resources, nil)
  end
end
