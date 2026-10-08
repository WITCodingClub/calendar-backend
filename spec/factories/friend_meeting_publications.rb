# frozen_string_literal: true

# == Schema Information
#
# Table name: friend_meeting_publications
#
#  id                  :bigint           not null, primary key
#  invitations_sent_at :datetime
#  last_error          :string
#  provider            :string           not null
#  sends_invitations   :boolean          default(FALSE), not null
#  status              :string           default("queued"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  friend_meeting_id   :bigint           not null
#
# Indexes
#
#  idx_friend_meeting_publications_unique  (friend_meeting_id,provider) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (friend_meeting_id => friend_meetings.id)
#
FactoryBot.define do
  factory :friend_meeting_publication do
    association :friend_meeting
    provider { "google" }

    trait :sends_invitations do
      sends_invitations { true }
    end

    trait :invitations_sent do
      sends_invitations { true }
      status { "published" }
      invitations_sent_at { Time.current }
    end
  end
end
