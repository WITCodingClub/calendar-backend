# frozen_string_literal: true

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
class Course::MeetingTimeRoom < ApplicationRecord
  self.table_name = "course_meeting_time_rooms"

  belongs_to :meeting_time, class_name: "Course::MeetingTime"
  belongs_to :room

  # A room being added or removed changes the calendar event location, so flag
  # the meeting time's enrolled users for resync (the meeting_time row itself
  # doesn't change, so its own callbacks won't fire).
  after_commit :resync_enrolled_users, on: [ :create, :destroy ]

  private

  def resync_enrolled_users
    meeting_time&.resync_enrolled_users!
  end
end
