# frozen_string_literal: true

# == Schema Information
#
# Table name: university_calendar_events
# Database name: primary
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
class UniversityCalendarEventSerializer
  def initialize(event)
    @event = event
  end

  def as_json(*)
    {
      id: @event.public_id,
      summary: @event.summary,
      description: @event.description,
      location: @event.location,
      start_time: @event.start_time.iso8601,
      end_time: @event.end_time.iso8601,
      all_day: @event.all_day,
      category: @event.category,
      organization: @event.organization,
      academic_term: @event.academic_term,
      term_id: @event.term&.public_id,
      excludes_classes: @event.excludes_classes?,
      formatted_date: @event.formatted_date,
      created_at: @event.created_at.iso8601,
      updated_at: @event.updated_at.iso8601
    }
  end

end
