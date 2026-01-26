defmodule AnomaExplorer.SettingsTest do
  @moduledoc """
  Tests for the Settings context, specifically app settings (envio URL).
  """
  use AnomaExplorer.DataCase, async: true

  alias AnomaExplorer.Settings
  alias AnomaExplorer.Settings.AppSetting

  describe "get_envio_url/0" do
    test "returns nil when not set" do
      clear_envio_url()
      assert Settings.get_envio_url() == nil
    end

    test "returns database value when set" do
      insert_envio_url("https://test.envio.dev/graphql")
      assert Settings.get_envio_url() == "https://test.envio.dev/graphql"
    end

    test "falls back to env var when database not set" do
      clear_envio_url()
      Application.put_env(:anoma_explorer, :envio_graphql_url, "https://env.envio.dev/graphql")

      assert Settings.get_envio_url() == "https://env.envio.dev/graphql"

      Application.delete_env(:anoma_explorer, :envio_graphql_url)
    end

    test "database value takes precedence over env var" do
      insert_envio_url("https://db.envio.dev/graphql")
      Application.put_env(:anoma_explorer, :envio_graphql_url, "https://env.envio.dev/graphql")

      assert Settings.get_envio_url() == "https://db.envio.dev/graphql"

      Application.delete_env(:anoma_explorer, :envio_graphql_url)
    end
  end

  describe "set_envio_url/1" do
    test "creates setting when not exists" do
      clear_envio_url()

      assert {:ok, %AppSetting{}} = Settings.set_envio_url("https://new.envio.dev/graphql")
      assert Settings.get_envio_url() == "https://new.envio.dev/graphql"
    end

    test "updates setting when exists" do
      insert_envio_url("https://old.envio.dev/graphql")

      assert {:ok, %AppSetting{}} = Settings.set_envio_url("https://updated.envio.dev/graphql")
      assert Settings.get_envio_url() == "https://updated.envio.dev/graphql"
    end

    test "sets description" do
      clear_envio_url()

      {:ok, setting} = Settings.set_envio_url("https://test.envio.dev/graphql")
      assert setting.description == "Envio Hyperindex GraphQL endpoint URL"
    end
  end

  describe "get_app_setting/1 and set_app_setting/3" do
    test "get_app_setting returns nil when not set" do
      assert Settings.get_app_setting("nonexistent_key") == nil
    end

    test "set_app_setting creates and retrieves setting" do
      assert {:ok, setting} = Settings.set_app_setting("test_key", "test_value", "A test setting")
      assert setting.key == "test_key"
      assert setting.value == "test_value"
      assert setting.description == "A test setting"

      assert Settings.get_app_setting("test_key") == "test_value"
    end

    test "set_app_setting updates existing setting" do
      Settings.set_app_setting("test_key", "initial", "Initial description")
      assert Settings.get_app_setting("test_key") == "initial"

      Settings.set_app_setting("test_key", "updated", "Updated description")
      assert Settings.get_app_setting("test_key") == "updated"
    end
  end

  describe "delete_app_setting/1" do
    test "deletes existing setting" do
      insert_envio_url("https://test.envio.dev/graphql")

      assert {:ok, _} = Settings.delete_app_setting("envio_graphql_url")
      assert Settings.get_app_setting("envio_graphql_url") == nil
    end

    test "returns error when not exists" do
      clear_envio_url()

      assert {:error, :not_found} = Settings.delete_app_setting("envio_graphql_url")
    end
  end

  # Helper functions
  defp insert_envio_url(url) do
    Repo.insert!(
      %AppSetting{key: "envio_graphql_url", value: url},
      on_conflict: {:replace, [:value]},
      conflict_target: :key
    )
  end

  defp clear_envio_url do
    Repo.delete_all(AppSetting)
    Application.delete_env(:anoma_explorer, :envio_graphql_url)
  end
end
