# frozen_string_literal: true

# == Schema Information
#
# Table name: friend_meetings
#
#  id             :bigint           not null, primary key
#  end_time       :datetime         not null
#  frequency      :string           default("one_time"), not null
#  invite_friends :boolean          default(FALSE), not null
#  location       :string
#  repeat_until   :date
#  start_time     :datetime         not null
#  title          :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  term_id        :bigint
#  user_id        :bigint           not null
#
# Indexes
#
#  index_friend_meetings_on_term_id  (term_id)
#  index_friend_meetings_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :friend_meeting do
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
  end
end
