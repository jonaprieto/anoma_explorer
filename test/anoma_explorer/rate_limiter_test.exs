defmodule AnomaExplorer.RateLimiterTest do
  use ExUnit.Case, async: false

  alias AnomaExplorer.RateLimiter

  # RateLimiter is already started by the application
  # No need to start it in tests

  describe "acquire/1" do
    test "allows requests under limit" do
      # Use unique keys to avoid interference from other tests
      key = "test_allow_#{System.unique_integer([:positive])}"
      assert :ok = RateLimiter.acquire(key)
      assert :ok = RateLimiter.acquire(key)
      assert :ok = RateLimiter.acquire(key)
    end

    test "blocks requests over limit" do
      key = "test_block_#{System.unique_integer([:positive])}"

      # Make 5 requests (at limit)
      for _ <- 1..5 do
        assert :ok = RateLimiter.acquire(key)
      end

      # 6th request should be rate limited
      assert {:error, :rate_limited} = RateLimiter.acquire(key)
    end

    test "different keys have independent limits" do
      key1 = "key1_#{System.unique_integer([:positive])}"
      key2 = "key2_#{System.unique_integer([:positive])}"

      # Fill up key1
      for _ <- 1..5 do
        assert :ok = RateLimiter.acquire(key1)
      end

      assert {:error, :rate_limited} = RateLimiter.acquire(key1)

      # key2 should still be available
      assert :ok = RateLimiter.acquire(key2)
    end
  end

  describe "status/1" do
    test "returns current count and max" do
      key = "status_test_#{System.unique_integer([:positive])}"

      assert {0, 5} = RateLimiter.status(key)

      RateLimiter.acquire(key)
      RateLimiter.acquire(key)

      assert {2, 5} = RateLimiter.status(key)
    end
  end

  describe "wait_and_acquire/2" do
    test "acquires immediately when under limit" do
      key = "wait_test_#{System.unique_integer([:positive])}"
      assert :ok = RateLimiter.wait_and_acquire(key, 100)
    end

    test "returns timeout error when limit exceeded and max wait exceeded" do
      key = "wait_timeout_#{System.unique_integer([:positive])}"

      # Fill the bucket
      for _ <- 1..5 do
        RateLimiter.acquire(key)
      end

      # Should timeout quickly with small max_wait
      assert {:error, :timeout} = RateLimiter.wait_and_acquire(key, 50)
    end
  end
end
