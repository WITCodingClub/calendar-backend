class GoogleCalendarCreateJob < ApplicationJob
  queue_as :high_priority

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    GoogleCalendarService.new(user).create_or_get_course_calendar
  end
end
