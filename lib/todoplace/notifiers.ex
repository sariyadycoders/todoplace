defmodule Todoplace.Notifiers do
  @moduledoc "shared notifier helpers"

  require Logger
  import Bamboo.{Email, SendGridHelper}

  def sendgrid_template(template_key, dynamic_fields) do
    dynamic_fields
    |> Enum.reduce(
      new_email()
      |> with_template(Application.get_env(:todoplace, Todoplace.Mailer)[template_key])
      |> with_bypass_list_management(true),
      fn {k, v}, e -> add_dynamic_field(e, k, v) end
    )
  end

  def deliver_later(email) do
    email |> Todoplace.Mailer.deliver_later()
  rescue
    exception ->
      error = Exception.format(:error, exception, __STACKTRACE__)
      Logger.error(error)
      {:error, exception}
  end

  def email_signature(organization) do
    Phoenix.View.render_to_string(TodoplaceWeb.EmailSignatureView, "show.html",
      organization: organization,
      user: organization.user
    )
  end

  def noreply_address(),
    do:
      Application.get_env(:todoplace, Todoplace.Mailer)
      |> Keyword.get(:no_reply_email)

  defmacro __using__(_) do
    quote do
      import Todoplace.Notifiers
      import Bamboo.Email
    end
  end
end
