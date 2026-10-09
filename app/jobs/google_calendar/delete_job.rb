# frozen_string_literal: true

module GoogleCalendar
  class DeleteJob < ApplicationJob
    queue_as :high

    def perform(calendar_id)
      GoogleCalendar::Provider.new.delete_calendar(calendar_id)
    rescue Google::Apis::ClientError => e
      raise unless e.status_code == 404 && e.message.include?("notFound")

      Rails.logger.info("Calendar #{calendar_id} already deleted or not found - treating as success")
    end
  end
end
