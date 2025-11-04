# frozen_string_literal: true

class GoogleCalendarDeleteJob < ApplicationJob
  queue_as :high

  def perform(calendar_id)
    GoogleCalendarService.new.delete_calendar(calendar_id)
  end

end
