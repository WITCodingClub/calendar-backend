# frozen_string_literal: true

# == Schema Information
#
# Table name: calendar_preferences
# Database name: primary
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
#  index_calendar_preferences_on_user_id    (user_id)
#  index_calendar_prefs_on_user_scope_type  (user_id,scope,event_type) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :calendar_preference do
    user
    scope { :global }
    event_type { nil }
    title_template { nil }
    description_template { nil }
    location_template { nil }
    reminder_settings { nil }
    color_id { nil }
    visibility { nil }

    trait :event_type_lecture do
      scope { :event_type }
      event_type { "lecture" }
      title_template { "{{course_code}}: {{title}}" }
      color_id { 1 }
    end

    trait :event_type_laboratory do
      scope { :event_type }
      event_type { "laboratory" }
      title_template { "{{title}} - Lab ({{room}})" }
      color_id { 7 }
    end

    trait :event_type_hybrid do
      scope { :event_type }
      event_type { "hybrid" }
      title_template { "{{title}} [{{schedule_type}}]" }
    end
  end
end
