# frozen_string_literal: true

class GoogleCalendarCreateJob < ApplicationJob
  queue_as :high

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    GoogleCalendarService.new(user).create_or_get_course_calendar
  end

end
