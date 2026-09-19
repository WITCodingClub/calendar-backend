# frozen_string_literal: true

# == Schema Information
#
# Table name: calendar_events
#
#  id                           :bigint           not null, primary key
#  end_time                     :datetime
#  event_data_hash              :string
#  external_ical_uid            :string
#  last_synced_at               :datetime
#  location                     :string
#  recurrence                   :text
#  start_time                   :datetime
#  summary                      :string
#  user_edited_fields           :jsonb
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  calendar_id                  :bigint           not null
#  external_event_id            :string           not null
#  final_exam_id                :bigint
#  meeting_time_id              :bigint
#  university_calendar_event_id :bigint
#
# Indexes
#
#  idx_calendar_events_on_calendar_id_meeting_time_id    (calendar_id,meeting_time_id)
#  idx_calendar_events_unique_final_exam                 (calendar_id,final_exam_id) UNIQUE WHERE (final_exam_id IS NOT NULL)
#  idx_calendar_events_unique_meeting_time               (calendar_id,meeting_time_id) UNIQUE WHERE (meeting_time_id IS NOT NULL)
#  idx_calendar_events_unique_university                 (calendar_id,university_calendar_event_id) UNIQUE WHERE (university_calendar_event_id IS NOT NULL)
#  index_calendar_events_on_calendar_id                  (calendar_id)
#  index_calendar_events_on_external_event_id            (external_event_id)
#  index_calendar_events_on_external_ical_uid            (external_ical_uid)
#  index_calendar_events_on_final_exam_id                (final_exam_id)
#  index_calendar_events_on_last_synced_at               (last_synced_at)
#  index_calendar_events_on_meeting_time_id              (meeting_time_id)
#  index_calendar_events_on_university_calendar_event_id (university_calendar_event_id)
#
# Foreign Keys
#
#  fk_rails_...  (calendar_id => calendars.id)
#  fk_rails_...  (meeting_time_id => course_meeting_times.id)
#
FactoryBot.define do
  factory :calendar_event do
    # The model validates exactly one of meeting_time_id / final_exam_id /
    # university_calendar_event_id against the raw id column, so the
    # association has to be persisted even when this factory is built (not
    # created), or the foreign key stays nil and the validation fails.
    association :course_calendar, strategy: :create
    association :meeting_time, factory: :course_meeting_time, strategy: :create
    sequence(:external_event_id) { |n| "factory-evt-#{n}" }

    trait :for_final_exam do
      meeting_time { nil }
      association :final_exam, strategy: :create
    end

    trait :for_university_event do
      meeting_time { nil }
      association :university_calendar_event, strategy: :create
    end

    trait :microsoft do
      association :course_calendar, :microsoft, strategy: :create
      external_ical_uid { Faker::Internet.uuid }
    end
  end
end
