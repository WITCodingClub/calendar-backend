# frozen_string_literal: true

class GoogleCalendarCreateJob < ApplicationJob
  queue_as :high

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    # Create or get the calendar
    GoogleCalendarService.new(user).create_or_get_course_calendar

    # Automatically sync events after calendar creation
    user.sync_course_schedule(force: true)
  end

end
