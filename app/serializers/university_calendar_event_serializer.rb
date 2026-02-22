# frozen_string_literal: true

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
