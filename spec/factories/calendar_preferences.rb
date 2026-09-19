# frozen_string_literal: true

# == Schema Information
#
# Table name: calendar_preferences
#
#  id                   :bigint           not null, primary key
#  description_template :text
#  event_type           :string
#  location_template    :text
#  reminder_settings    :jsonb
#  scope                :integer          not null
#  title_template       :text
#  visibility           :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  color_id             :integer
#  user_id              :bigint           not null
#
# Indexes
#
#  index_calendar_preferences_on_user_id     (user_id)
#  index_calendar_prefs_on_user_scope_type   (user_id,scope,event_type) UNIQUE
#  index_calendar_prefs_one_global_per_user  (user_id) UNIQUE WHERE (scope = 0)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :calendar_preference do
    association :user
    scope { :global }

    trait :for_event_type do
      scope { :event_type }
      event_type { "assignment" }
    end

    trait :uni_cal_global do
      scope { :uni_cal_global }
    end

    trait :uni_cal_category do
      scope { :uni_cal_category }
      event_type { "holiday" }
    end
  end
end
