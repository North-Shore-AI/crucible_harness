defmodule CrucibleHarness.Errors.Classifier do
  @moduledoc false

  @default_retryable [:timeout, :connection_refused, :rate_limited, :temporarily_unavailable]
  @default_permanent [:invalid_query, :authentication_failed, :bad_request]
  @default_retryable_http [429, 500, 502, 503, 504]
  @default_permanent_http [400, 401, 403, 404, 422]

  def retryable?(error, config \\ %{})

  def retryable?({:http_status, status}, config) when is_integer(status) do
    retryable_http = Map.get(config, :retryable_http_statuses, @default_retryable_http)
    permanent_http = Map.get(config, :permanent_http_statuses, @default_permanent_http)

    cond do
      status in permanent_http -> false
      status in retryable_http -> true
      status >= 500 -> true
      true -> false
    end
  end

  def retryable?(error, config) do
    retryable_errors = Map.get(config, :retryable_errors, @default_retryable)
    permanent_errors = Map.get(config, :permanent_errors, @default_permanent)

    cond do
      error in permanent_errors -> false
      error in retryable_errors -> true
      true -> false
    end
  end
end
