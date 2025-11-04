class CourseProcessorJob < ApplicationJob
  queue_as :high_priority

  def perform(courses, user_id)
    user = User.find_by(id: user_id)
    return unless user

    CourseProcessorService.new(courses, user).call
  end
end
