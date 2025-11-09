# frozen_string_literal: true

class SyncMeetingTimeJob < ApplicationJob
  queue_as :high

  def perform(user_id, meeting_time_id)
    user = User.find(user_id)
    user.sync_meeting_time(meeting_time_id, force: true)
  end

end
