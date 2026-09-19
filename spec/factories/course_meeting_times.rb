# frozen_string_literal: true

# == Schema Information
#
# Table name: course_meeting_times
#
#  id                    :bigint           not null, primary key
#  begin_time            :integer          not null
#  day_of_week           :integer          not null
#  end_date              :datetime         not null
#  end_time              :integer          not null
#  hours_week            :integer
#  meeting_schedule_type :integer          not null
#  meeting_type          :integer          not null
#  start_date            :datetime         not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  course_id             :bigint           not null
#
# Indexes
#
#  index_course_meeting_times_on_course_id    (course_id)
#  index_course_meeting_times_on_day_of_week  (day_of_week)
#
# Foreign Keys
#
#  fk_rails_...  (course_id => courses.id)
#
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
