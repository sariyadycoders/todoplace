defmodule Todoplace.TenantManager do
  alias Todoplace.Repo

  def create_tenant_schema(tenant_name) when is_binary(tenant_name) do
    schema_name = "#{Application.get_env(:triplex, :prefix)}#{tenant_name}"
    sql = "CREATE SCHEMA IF NOT EXISTS #{schema_name}"
    case Repo.query(sql) do
      {:ok, _result} -> {:ok, "Schema created"}
      {:error, reason} -> {:error, reason}
    end
  end

  def drop_tenant_schema(tenant_name) when is_binary(tenant_name) do
    schema_name = "#{Application.get_env(:triplex, :prefix)}#{tenant_name}"
    sql = "DROP SCHEMA IF EXISTS #{schema_name} CASCADE"
    case Repo.query(sql) do
      {:ok, _result} -> {:ok, "Schema dropped"}
      {:error, reason} -> {:error, reason}
    end
  end
end
