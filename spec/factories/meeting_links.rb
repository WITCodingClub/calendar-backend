# frozen_string_literal: true

# == Schema Information
#
# Table name: meeting_links
#
#  id                :bigint           not null, primary key
#  duration_minutes  :integer          not null
#  ends_on           :date             not null
#  expires_at        :datetime         not null
#  revoked_at        :datetime
#  starts_on         :date             not null
#  title             :string
#  token_digest      :string           not null
#  used_at           :datetime
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  friend_meeting_id :bigint
#  guest_user_id     :bigint
#  user_id           :bigint           not null
#
# Indexes
#
#  index_meeting_links_on_friend_meeting_id  (friend_meeting_id)
#  index_meeting_links_on_guest_user_id      (guest_user_id)
#  index_meeting_links_on_token_digest       (token_digest) UNIQUE
#  index_meeting_links_on_user_id            (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (friend_meeting_id => friend_meetings.id) ON DELETE => nullify
#  fk_rails_...  (guest_user_id => users.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :meeting_link do
    association :user
    starts_on { Time.zone.tomorrow }
    ends_on { starts_on + 6 }
    duration_minutes { 30 }

    trait :titled do
      title { Faker::Lorem.words(number: 3).join(" ").capitalize }
    end

    trait :revoked do
      revoked_at { Time.current }
    end

    trait :used do
      used_at { Time.current }
      friend_meeting { association :friend_meeting, :with_guest, user: user }
    end

    # The model refuses a past expiry on create, so move it after the save.
    trait :expired do
      after(:create) { |link| link.update_columns(expires_at: 1.minute.ago) }
    end
  end
end
