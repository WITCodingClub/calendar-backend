# frozen_string_literal: true

# Deletes one event from a Microsoft calendar. Enqueued when a Microsoft
# CalendarEvent row is destroyed, so the live Outlook event goes too.
class MicrosoftGraphEventDeleteJob < ApplicationJob
  queue_as :high

  discard_on MicrosoftGraph::AuthError

  def perform(oauth_credential_id, event_id, ical_uid = nil)
    return if event_id.blank?

    # Without the credential there is no token to act with. The person
    # disconnected the account, so the calendar is theirs to clean up.
    credential = OauthCredential.microsoft.find_by(id: oauth_credential_id)
    return unless credential

    MicrosoftGraphCalendarService.new(credential.user, credential: credential)
                                 .delete_calendar_event(event_id, ical_uid)
  end
end
