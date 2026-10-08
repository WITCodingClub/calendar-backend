# frozen_string_literal: true

require "rails_helper"

RSpec.describe FriendMeetingAttendee do
  subject { create(:friend_meeting_attendee) }

  it { is_expected.to belong_to(:friend_meeting) }
  it { is_expected.to belong_to(:user) }
  it { is_expected.to validate_uniqueness_of(:user_id).scoped_to(:friend_meeting_id) }
end
