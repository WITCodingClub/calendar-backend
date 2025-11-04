# frozen_string_literal: true

# == Schema Information
#
# Table name: meeting_times
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  begin_time            :integer          not null
#  day_of_week           :integer
#  end_date              :datetime         not null
#  end_time              :integer          not null
#  hours_week            :integer
#  meeting_schedule_type :integer
#  meeting_type          :integer
#  start_date            :datetime         not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  course_id             :bigint           not null
#  room_id               :bigint           not null
#
# Indexes
#
#  index_meeting_times_on_course_id    (course_id)
#  index_meeting_times_on_day_of_week  (day_of_week)
#  index_meeting_times_on_room_id      (room_id)
#
# Foreign Keys
#
#  fk_rails_...  (course_id => courses.id)
#  fk_rails_...  (room_id => rooms.id)
#
FactoryBot.define do
  factory :meeting_time do
    course
    room

    start_date { 3.days.from_now }
    end_date { 3.months.from_now }
    begin_time { 1000 } # 10:00 AM
    end_time { 1150 } # 11:50 AM
    day_of_week { :monday }
    hours_week { 2 }
    meeting_schedule_type { :lecture }
    meeting_type { :class_meeting }
  end
end
