defmodule Todoplace.BookingEventTemplates do
  @moduledoc false
  def body(key) do
    key = if key == :hidden, do: :reserved, else: key

    case key do
      :marketing ->
        """
        <p><span style="color: rgb(0, 0, 0);">Hello,</span></p>
        <p><span style="color: rgb(0, 0, 0);">I’m very excited to extend an exclusive invitation to {{photography_company_s_name}}’s upcoming booking event, and as a valued client, I wanted to ensure you're among the first to know. </span></p>
        <p><span style="color: rgb(0, 0, 0);">These limited edition booking events are a rare opportunity to capture unforgettable moments, and I’m eager to reserve a spot just for you. These events only happen a few times a year, and given the high demand, availability tends to fill up quickly.</span></p>
        <p><span style="color: rgb(0, 0, 0);">To guarantee your place, I encourage you to secure your booking by clicking the following link:</span></p>
        <p>{{view_proposal_button}}</p>
        <p><span style="color: rgb(0, 0, 0);">I’m so excited to capture these special moments for you.</span></p>
        """

      :reserved ->
        """
        <p><span style="color: rgb(0, 0, 0);">Hello {{client_first_name}},</span></p>
        <p><span style="color: rgb(0, 0, 0);">I am so very excited you are taking advantage of my upcoming booking event, {{booking_event_name}}! I’ve reserved a spot especially for and to officially book your session with me, please: <ol> <li> Review your proposal </li> <li>Read and sign your contract </li> <li>Fill out the initial questionnaire </li> <li> Pay your retainer </li>  </ol></span></p>
        <p><span style="color: rgb(0, 0, 0);">{{view_proposal_button}} </span></p>
        <p><span style="color: rgb(0, 0, 0);">Please note that your session will not be considered officially booked until the contract is signed and a retainer is paid. Once you are officially booked, the date and time will be held for you and all other inquiries will be declined. For this reason, your retainer is non-refundable.        </span></p>
        <p><span style="color: rgb(0, 0, 0);"> When you’re officially booked, look for a confirmation email from me with more details! </span></p>
        <p><span style="color: rgb(0, 0, 0);">I can’t wait to work with you!</span></p>
        <p><span style="color: rgb(0, 0, 0);">Kind regards,</span></p>
        """

      :open ->
        """
        <p><span style="color: rgb(0, 0, 0);">Hello {{client_first_name}},</span></p>
        <p><span style="color: rgb(0, 0, 0);">I am so very excited you are taking advantage of my upcoming booking event, {{booking_event_name}}! I’ve reserved a spot especially for and to officially book your session with me, please: <ol> <li> Review your proposal </li> <li>Read and sign your contract </li> <li>Fill out the initial questionnaire </li> <li> Pay your retainer </li>  </ol></span></p>
        <p><span style="color: rgb(0, 0, 0);">{{view_proposal_button}} </span></p>
        <p><span style="color: rgb(0, 0, 0);">Please note that your session will not be considered officially booked until the contract is signed and a retainer is paid. Once you are officially booked, the date and time will be held for you and all other inquiries will be declined. For this reason, your retainer is non-refundable.        </span></p>
        <p><span style="color: rgb(0, 0, 0);"> When you’re officially booked, look for a confirmation email from me with more details! </span></p>
        <p><span style="color: rgb(0, 0, 0);">I can’t wait to work with you!</span></p>
        <p><span style="color: rgb(0, 0, 0);">Kind regards,</span></p>
        """

      :booked ->
        """
        <p><span style="color: rgb(0, 0, 0);">Hello {{client_first_name}},</span></p>
        <p><span style="color: rgb(0, 0, 0);">Your session for {{booking_event_name}} with {{photography_company_s_name}} has been successfully rescheduled for {{session_date}} at {{session_time}} at {{session_location}}.</span></p>
        <p><span style="color: rgb(0, 0, 0);">You can find a copy of your revised invoice on your client portal:</span></p>
        <p><span style="color: rgb(0, 0, 0);">{{view_proposal_button}} </span></p>
        <p><span style="color: rgb(0, 0, 0);"> Please reach out with any questions otherwise I look forward to capturing these memories for you. </span></p>
        <p><span style="color: rgb(0, 0, 0);">Thanks so much, </span></p>
        """

      :date ->
        """
        <p><span style="color: rgb(0, 0, 0);">Hello,</span></p>
        <p><span style="color: rgb(0, 0, 0);">I wanted to share some important information about our upcoming session, {{booking_event_name}}.</span></p>
        <p><span style="color: rgb(0, 0, 0);">Please reach out with any questions via email or by cell phone{{photographer_cell}}.</span></p>
        <p><span style="color: rgb(0, 0, 0);">Thanks so much,</span></p>
        """
    end
  end
end
