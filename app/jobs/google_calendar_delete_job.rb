# frozen_string_literal: true

class GoogleCalendarDeleteJob < ApplicationJob
  queue_as :high

  def perform(calendar_id)
    GoogleCalendarService.new.delete_calendar(calendar_id)
  rescue Google::Apis::ClientError => e
    # If calendar is already deleted (404 Not Found), consider it successful
    raise unless e.status_code == 404 && e.message.include?("notFound")

    Rails.logger.info("Calendar #{calendar_id} already deleted or not found - treating as success")
  end

end
