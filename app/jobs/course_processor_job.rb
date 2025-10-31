class CourseProcessorJob < ApplicationJob
  queue_as :default

  def perform(courses, user_id)
    user = User.find(user_id)
    CourseProcessorService.new(courses, user).call
  end
end
