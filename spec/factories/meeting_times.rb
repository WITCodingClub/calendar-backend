# == Schema Information
#
# Table name: meeting_times
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  begin_time            :integer          not null
#  end_date              :datetime         not null
#  end_time              :integer          not null
#  friday                :boolean
#  hours_week            :integer
#  meeting_schedule_type :integer
#  meeting_type          :integer
#  monday                :boolean
#  saturday              :boolean
#  start_date            :datetime         not null
#  sunday                :boolean
#  thursday              :boolean
#  tuesday               :boolean
#  wednesday             :boolean
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  course_id             :bigint           not null
#  room_id               :bigint           not null
#
# Indexes
#
#  index_meeting_times_on_course_id  (course_id)
#  index_meeting_times_on_room_id    (room_id)
#
# Foreign Keys
#
#  fk_rails_...  (course_id => courses.id)
#  fk_rails_...  (room_id => rooms.id)
#
FactoryBot.define do
  factory :meeting_time do
    
  end
end
