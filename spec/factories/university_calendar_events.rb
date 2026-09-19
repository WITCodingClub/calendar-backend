# frozen_string_literal: true

# == Schema Information
#
# Table name: university_calendar_events
#
#  id              :bigint           not null, primary key
#  academic_term   :string
#  all_day         :boolean          default(FALSE), not null
#  category        :string
#  description     :text
#  end_time        :datetime         not null
#  event_type_raw  :string
#  ics_uid         :string           not null
#  last_fetched_at :datetime
#  location        :string
#  organization    :string
#  recurrence      :text
#  source_url      :string
#  start_time      :datetime         not null
#  summary         :text             not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  term_id         :bigint
#
# Indexes
#
#  index_university_calendar_events_on_academic_term            (academic_term)
#  index_university_calendar_events_on_category                 (category)
#  index_university_calendar_events_on_ics_uid                  (ics_uid) UNIQUE
#  index_university_calendar_events_on_start_time_and_end_time  (start_time,end_time)
#  index_university_calendar_events_on_term_id                  (term_id)
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#
FactoryBot.define do
  factory :university_calendar_event do
    sequence(:ics_uid) { |n| "factory-ics-#{n}@calendar" }
    summary { "Factory University Event" }
    start_time { Time.zone.local(2026, 9, 1, 9, 0) }
    end_time { Time.zone.local(2026, 9, 1, 10, 0) }
  end
end
