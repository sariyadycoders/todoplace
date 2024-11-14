defmodule Todoplace.Shared do
  def get_app_params() do
    ctx_app = Mix.Phoenix.context_app()
    otp_app = Mix.Phoenix.otp_app()
    base = Mix.Phoenix.context_base(ctx_app)
    project_name = base |> String.capitalize()
    repo = Module.concat([base, "Repo"])
    repo_alias = if String.ends_with?(Atom.to_string(repo), ".Repo"), do: "", else: ", as: Repo"
    web_path = Mix.Phoenix.web_path(ctx_app)
    base_path = "lib/#{Mix.Phoenix.otp_app() |> Atom.to_string()}"
    web_module = Mix.Phoenix.web_module(base)

    %{
      ctx_app: ctx_app,
      web_module: web_module,
      web_path: web_path,
      base_path: base_path,
      otp_app: otp_app,
      base: Module.concat([base]),
      repo: repo,
      repo_alias: repo_alias,
      project_name: project_name
    }
  end
end
