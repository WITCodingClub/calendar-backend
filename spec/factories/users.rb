# frozen_string_literal: true

# == Schema Information
#
# Table name: users
# Database name: primary
#
#  id                           :bigint           not null, primary key
#  access_level                 :integer          default("user"), not null
#  calendar_needs_sync          :boolean          default(FALSE), not null
#  calendar_token               :string
#  first_name                   :string
#  last_calendar_sync_at        :datetime
#  last_name                    :string
#  notifications_disabled_until :datetime
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#
# Indexes
#
#  index_users_on_calendar_needs_sync    (calendar_needs_sync)
#  index_users_on_calendar_token         (calendar_token) UNIQUE
#  index_users_on_last_calendar_sync_at  (last_calendar_sync_at)
#
FactoryBot.define do
  factory :user do
    first_name { "John" }
    last_name { "Doe" }
    access_level { :user }

    trait :with_google_credential do
      after(:create) do |user|
        create(:oauth_credential, user: user)
      end
    end

    trait :admin do
      access_level { :admin }
    end

    trait :super_admin do
      access_level { :super_admin }
    end

    trait :owner do
      access_level { :owner }
    end
  end
end
