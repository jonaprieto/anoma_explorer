defmodule AnomaExplorer.HTTPClient.FinchClient do
  @moduledoc """
  HTTP client implementation using Erlang's :httpc.
  Note: Named FinchClient for backwards compatibility.
  """

  @behaviour AnomaExplorer.HTTPClient

  @impl true
  def post(url, body, headers \\ []) do
    # Ensure inets is started
    :inets.start()
    :ssl.start()

    headers = [{"content-type", "application/json"} | headers]
    # Convert headers to charlists for :httpc
    http_headers = Enum.map(headers, fn {k, v} -> {to_charlist(k), to_charlist(v)} end)

    body_json = Jason.encode!(body)

    request = {to_charlist(url), http_headers, ~c"application/json", body_json}

    http_options = [
      timeout: 30_000,
      connect_timeout: 10_000,
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    ]

    options = [body_format: :binary]

    case :httpc.request(:post, request, http_options, options) do
      {:ok, {{_http_version, status, _reason_phrase}, _headers, response_body}}
      when status in 200..299 ->
        case Jason.decode(response_body) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, _} -> {:ok, response_body}
        end

      {:ok, {{_http_version, status, _reason_phrase}, _headers, response_body}} ->
        body_str = if is_binary(response_body), do: response_body, else: to_string(response_body)
        {:error, {:http_error, status, body_str}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
