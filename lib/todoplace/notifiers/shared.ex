defmodule Notifiers.Shared do
  @moduledoc """
  This module provides functions for delivering transactional emails to recipients using SendGrid.

  It supports delivering emails in different scenarios, such as for jobs and client messages, and handles
  the generation of email templates and recipient mapping.

  ## Usage Example:
  ```elixir
  # Deliver a transactional email for a job
  Notifiers.Shared.deliver_transactional_email(params, recipients, job)

  # Deliver a transactional email for a client message
  Notifiers.Shared.deliver_transactional_email(params, recipients, message)

  # Deliver a generic transactional email
  Notifiers.Shared.deliver_transactional_email(params, recipients)
  """
  use Todoplace.Notifiers
  alias Todoplace.{Repo, Job, ClientMessage, Messages}
  require Logger

  def deliver_transactional_email(params, recipients, %Job{} = job) do
    client = job |> Repo.preload(:client) |> Map.get(:client)
    reply_to = Messages.email_address(job)

    Logger.info("------")
    Logger.info("[Reply to] Monitor this: #{inspect(reply_to)}")
    Logger.info("[Reply to] Job id: #{inspect(job.id)}")
    Logger.info("------")

    deliver_transactional_email(params, recipients, reply_to, client)
  end

  def deliver_transactional_email(params, recipients, %ClientMessage{job: job} = message) do
    {reply_to, client} =
      if job do
        {Messages.email_address(job), job.client}
      else
        %{client_message_recipients: [%{client: %{organization: organization} = client} | _]} =
          Repo.preload(message, client_message_recipients: [client: :organization])

        {Messages.email_address(organization), client}
      end

    params = if Map.get(params, :button), do: Map.delete(params, :button), else: params
    deliver_transactional_email(params, recipients, reply_to, client)
  end

  def deliver_transactional_email(params, recipients, reply_to, client) do
    client = client |> Repo.preload(organization: [:user])
    %{organization: organization} = client

    params =
      Map.merge(
        %{
          organization_name: organization.name,
          email_signature: email_signature(organization)
        },
        params
      )
      |> Map.merge(logo_url(organization))

    from_display = organization.name

    :client_transactional_template
    |> sendgrid_template(params)
    |> put_header("reply-to", "#{from_display} <#{reply_to}>")
    |> from({from_display, noreply_address()})
    |> to(map_recipients(Map.get(recipients, "to")))
    |> cc(map_recipients(Map.get(recipients, "cc")))
    |> bcc(map_recipients(Map.get(recipients, "bcc")))
    |> deliver_later()
  end

  def deliver_transactional_email(params, recipients) do
    sendgrid_template(:generic_transactional_template, params)
    |> to(map_recipients(Map.get(recipients, "to")))
    |> cc(map_recipients(Map.get(recipients, "cc")))
    |> bcc(map_recipients(Map.get(recipients, "bcc")))
    |> from(noreply_address())
    |> deliver_later()
  end

  def logo_url(organization) do
    case Todoplace.Profiles.logo_url(organization) do
      nil -> %{organization_name: organization.name}
      url -> %{logo_url: url}
    end
  end

  def map_recipients(nil), do: nil

  def map_recipients(recipients) do
    if is_list(recipients) do
      Enum.map(recipients, &{:email, String.trim(&1)})
    else
      String.split(recipients, ";")
      |> Enum.map(&{:email, String.trim(&1)})
    end
  end
end
