# frozen_string_literal: true

FactoryBot.define do
  factory :course_meeting_time, class: "Course::MeetingTime" do
    association :course
    day_of_week { :monday }
    begin_time { 900 }
    end_time { 1015 }
    meeting_schedule_type { :lecture }
    meeting_type { :class_meeting }
    start_date { course.start_date }
    end_date { course.end_date }
  end
end
