defmodule AnomaExplorer.Indexer.Client do
  @moduledoc """
  Client for interacting with the Envio Hyperindex GraphQL endpoint.

  Provides helper functions to access the configured Envio endpoint
  and execute GraphQL queries against the indexed blockchain data.
  """

  alias AnomaExplorer.Settings

  @doc """
  Returns the configured Envio GraphQL URL, or nil if not set.
  Checks database first, then falls back to environment variable.
  """
  @spec graphql_url() :: String.t() | nil
  def graphql_url do
    Settings.get_envio_url()
  end

  @doc """
  Returns true if the Envio GraphQL endpoint is configured.
  """
  @spec configured?() :: boolean()
  def configured? do
    case graphql_url() do
      nil -> false
      "" -> false
      _url -> true
    end
  end

  @doc """
  Tests the connection to the configured GraphQL endpoint.
  Returns {:ok, message} on success, {:error, message} on failure.
  """
  @spec test_connection() :: {:ok, String.t()} | {:error, String.t()}
  def test_connection do
    case graphql_url() do
      nil -> {:error, "Indexer endpoint not configured"}
      "" -> {:error, "Indexer endpoint not configured"}
      url -> test_connection(url)
    end
  end

  @doc """
  Tests a specific URL for GraphQL connectivity.
  Useful for validating a URL before saving.
  """
  @spec test_connection(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def test_connection(url) when is_binary(url) and url != "" do
    :inets.start()
    :ssl.start()

    query = """
    {
      Transaction(limit: 1) { id }
    }
    """

    body = Jason.encode!(%{query: query})

    request =
      {to_charlist(url), [{~c"content-type", ~c"application/json"}], ~c"application/json", body}

    http_options = [
      timeout: 10_000,
      connect_timeout: 5_000,
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    ]

    case :httpc.request(:post, request, http_options, [body_format: :binary]) do
      {:ok, {{_http_version, 200, _reason}, _headers, response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"data" => _}} -> {:ok, "Connected successfully"}
          {:ok, %{"errors" => errors}} -> {:error, "GraphQL error: #{inspect(errors)}"}
          _ -> {:error, "Invalid response format"}
        end

      {:ok, {{_http_version, status, _reason}, _headers, _body}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, "Connection failed: #{format_connection_error(reason)}"}
    end
  end

  def test_connection(_), do: {:error, "Invalid URL"}

  @doc """
  Returns true if the endpoint is configured AND working.
  Performs an actual connection test.
  """
  @spec working?() :: boolean()
  def working? do
    case test_connection() do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp format_connection_error({:failed_connect, _}), do: "Unable to reach server"
  defp format_connection_error(:timeout), do: "Connection timed out"
  defp format_connection_error(reason), do: inspect(reason)
end
