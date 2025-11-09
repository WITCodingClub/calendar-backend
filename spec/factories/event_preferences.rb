# frozen_string_literal: true

# == Schema Information
#
# Table name: event_preferences
# Database name: primary
#
#  id                   :bigint           not null, primary key
#  description_template :text
#  location_template    :text
#  preferenceable_type  :string           not null
#  reminder_settings    :jsonb
#  title_template       :text
#  visibility           :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  color_id             :integer
#  preferenceable_id    :bigint           not null
#  user_id              :bigint           not null
#
# Indexes
#
#  index_event_preferences_on_preferenceable     (preferenceable_type,preferenceable_id)
#  index_event_preferences_on_user_id            (user_id)
#  index_event_prefs_on_preferenceable           (preferenceable_type,preferenceable_id)
#  index_event_prefs_on_user_and_preferenceable  (user_id,preferenceable_type,preferenceable_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :event_preference do
    user
    preferenceable factory: %i[meeting_time]
    title_template { nil }
    description_template { nil }
    reminder_settings { [{ "minutes" => 60, "method" => "popup" }] }
    color_id { nil }
    visibility { nil }

    trait :with_title do
      title_template { "{{day_abbr}} {{start_time}}: {{title}}" }
    end

    trait :with_description do
      description_template { "{{course_code}}\nLocation: {{location}}\nInstructor: {{faculty}}" }
    end

    trait :with_color do
      color_id { 9 }
    end

    trait :for_google_calendar_event do
      preferenceable factory: %i[google_calendar_event]
    end
  end
end
