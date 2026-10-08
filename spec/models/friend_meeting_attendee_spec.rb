# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: friend_meeting_attendees
#
#  id                :bigint           not null, primary key
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  friend_meeting_id :bigint           not null
#  user_id           :bigint           not null
#
# Indexes
#
#  idx_friend_meeting_attendees_unique        (friend_meeting_id,user_id) UNIQUE
#  index_friend_meeting_attendees_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (friend_meeting_id => friend_meetings.id)
#  fk_rails_...  (user_id => users.id)
#
RSpec.describe FriendMeetingAttendee do
  subject { create(:friend_meeting_attendee) }

  it { is_expected.to belong_to(:friend_meeting) }
  it { is_expected.to belong_to(:user) }
  it { is_expected.to validate_uniqueness_of(:user_id).scoped_to(:friend_meeting_id) }
end
