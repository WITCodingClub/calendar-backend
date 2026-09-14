# frozen_string_literal: true

FactoryBot.define do
  factory :course_meeting_time_room, class: "Course::MeetingTimeRoom" do
    association :meeting_time, factory: :course_meeting_time
    association :room
  end
end
