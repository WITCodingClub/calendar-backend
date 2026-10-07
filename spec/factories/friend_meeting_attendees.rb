# frozen_string_literal: true

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
FactoryBot.define do
  factory :friend_meeting_attendee do
    association :friend_meeting
    association :user
  end
end
