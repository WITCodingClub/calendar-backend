# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: course_meeting_time_rooms
#
#  id              :bigint           not null, primary key
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  meeting_time_id :bigint           not null
#  room_id         :bigint           not null
#
# Indexes
#
#  index_course_meeting_time_rooms_on_meeting_time_id_and_room_id  (meeting_time_id,room_id) UNIQUE
#  index_course_meeting_time_rooms_on_room_id                      (room_id)
#
# Foreign Keys
#
#  fk_rails_...  (meeting_time_id => course_meeting_times.id)
#  fk_rails_...  (room_id => rooms.id)
#
RSpec.describe Course::MeetingTimeRoom, type: :model do
  it { is_expected.to belong_to(:meeting_time).class_name("Course::MeetingTime") }
  it { is_expected.to belong_to(:room) }
end
