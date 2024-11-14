defmodule TodoplaceWeb.JobDownloadController do
  use TodoplaceWeb, :controller

  import TodoplaceWeb.BookingProposalLive.Shared, only: [get_print_credit: 1, get_amount: 1]
  import Todoplace.Profiles, only: [logo_url: 1]
  alias Todoplace.{Repo, BookingProposal, Contracts}

  def download_invoice_pdf(conn, %{"booking_proposal_id" => booking_proposal_id}) do
    %{
      job:
        %{
          client: client,
          shoots: shoots,
          package:
            %{contract: contract, organization: %{user: photographer} = organization} = package
        } = job
    } =
      proposal =
      booking_proposal_id
      |> BookingProposal.by_id()
      |> BookingProposal.preloads()
      |> Repo.preload([:questionnaire, :answer, job: [package: [:contract]]])

    print_credit = get_print_credit(package)
    amount = get_amount(print_credit)
    organization_logo_url = logo_url(organization)

    contract_content =
      if contract do
        Contracts.contract_content(
          contract,
          package,
          TodoplaceWeb.Helpers
        )
      end

    TodoplaceWeb.PDFView.render("job_invoice.html", %{
      read_only: true,
      job: job,
      proposal: proposal,
      photographer: photographer,
      organization: organization,
      client: client,
      shoots: shoots,
      package: package,
      contract: contract,
      organization_logo_url: organization_logo_url,
      contract_content: contract_content,
      print_credit: print_credit,
      amount: amount
    })
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
    |> PdfGenerator.generate(
      page_size: "A5",
      shell_params: [
        "--footer-right",
        "[page] / [toPage]",
        "--footer-font-size",
        "5",
        "--footer-font-name",
        "Montserrat"
      ]
    )
    |> then(fn {:ok, path} ->
      conn
      |> put_resp_content_type("pdf")
      |> put_resp_header(
        "content-disposition",
        TodoplaceWeb.GalleryDownloadsController.encode_header_value("job_invoice.pdf")
      )
      |> send_resp(200, File.read!(path))
    end)
  end
end

defmodule TodoplaceWeb.JobDownloadHTML do
  use TodoplaceWeb, :html
  import TodoplaceWeb.LiveHelpers, only: [icon: 1, classes: 2]
  import TodoplaceWeb.ViewHelpers


  embed_templates "templates/*"
end
