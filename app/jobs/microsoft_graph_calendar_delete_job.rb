# frozen_string_literal: true

# Deletes a course calendar from a person's Microsoft mailbox. Enqueued when a
# Microsoft CourseCalendar row is destroyed.
class MicrosoftGraphCalendarDeleteJob < ApplicationJob
  queue_as :high

  discard_on MicrosoftGraph::AuthError

  def perform(oauth_credential_id, calendar_id)
    return if calendar_id.blank?

    credential = OauthCredential.microsoft.find_by(id: oauth_credential_id)
    return unless credential

    MicrosoftGraphCalendarService.new(credential.user, credential: credential).delete_calendar(calendar_id)
  end
end
