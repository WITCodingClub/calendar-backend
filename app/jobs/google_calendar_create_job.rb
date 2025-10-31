class GoogleCalendarCreateJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find(user_id)
    GoogleCalendarService.new(user).create_or_get_course_calendar
  end
end
