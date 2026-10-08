# frozen_string_literal: true

# == Schema Information
#
# Table name: friend_meetings
#
#  id              :bigint           not null, primary key
#  cancelled_at    :datetime
#  end_time        :datetime         not null
#  frequency       :string           default("one_time"), not null
#  guest_email     :string
#  guest_name      :string
#  idempotency_key :string
#  invite_friends  :boolean          default(FALSE), not null
#  location        :string
#  repeat_until    :date
#  start_time      :datetime         not null
#  title           :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  term_id         :bigint
#  user_id         :bigint           not null
#
# Indexes
#
#  idx_friend_meetings_unique_idempotency_key  (user_id,idempotency_key) UNIQUE WHERE (idempotency_key IS NOT NULL)
#  index_friend_meetings_on_term_id            (term_id)
#  index_friend_meetings_on_user_id            (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :friend_meeting do
    # The places the meeting goes, in order, for example %w[google ics]. The
    # first calendar provider sends the invitations when invite_friends is on.
    transient do
      destinations { [] }
    end

    association :user
    title { Faker::Lorem.words(number: 3).join(" ").capitalize }
    start_time { 2.days.from_now.change(hour: 15, min: 0) }
    end_time { start_time + 1.hour }

    trait :weekly do
      frequency { "weekly" }
      association :term
      repeat_until { (start_time + 8.weeks).to_date }
    end

    trait :invite_friends do
      invite_friends { true }
    end

    # A meeting from a one-time meeting link. Synthetic guest, no real person.
    trait :with_guest do
      guest_name { "Sample Guest" }
      sequence(:guest_email) { |n| "guest#{n}@example.com" }
    end

    trait :cancelled do
      cancelled_at { Time.current }
    end

    after(:create) do |meeting, context|
      invites = meeting.invite_friends? || meeting.guest_email?
      sender  = (context.destinations & FriendMeetingPublication::CALENDAR_PROVIDERS).first if invites
      context.destinations.each do |provider|
        create(:friend_meeting_publication, friend_meeting: meeting, provider: provider,
                                            status:            provider == "ics" ? "published" : "queued",
                                            sends_invitations: provider == sender)
      end
    end
  end
end
