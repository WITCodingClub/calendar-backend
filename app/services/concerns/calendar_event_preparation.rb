# frozen_string_literal: true

# The provider-neutral half of a calendar sync: how an event is keyed to its
# tracking row, which record it came from, and how the person's preferences
# shape it. GoogleCalendar::Provider and MicrosoftGraph::CalendarProvider share it.
module CalendarEventPreparation
  extend ActiveSupport::Concern

  private

  def build_event_key(e)
    if e.meeting_time_id
      "mt_#{e.meeting_time_id}"
    elsif e.final_exam_id
      "fe_#{e.final_exam_id}"
    else
      "ue_#{e.university_calendar_event_id}"
    end
  end

  def build_event_key_from_hash(e)
    if e[:meeting_time_id]
      "mt_#{e[:meeting_time_id]}"
    elsif e[:final_exam_id]
      "fe_#{e[:final_exam_id]}"
    elsif e[:university_calendar_event_id]
      "ue_#{e[:university_calendar_event_id]}"
    end
  end

  SYNCABLE_KEYS = {
    meeting_time_id: -> { Course::MeetingTime.includes(rooms: :building, course: [ :faculties, :term ]) },
    final_exam_id: -> { FinalExam.includes(course: [ :faculties, :term ]) },
    university_calendar_event_id: -> { UniversityCalendarEvent.all }
  }.freeze

  # Loads the records behind all the events in one query for each kind, with
  # the associations that the templates read. resolve_syncable then reads them
  # from memory, so a sync does not send queries once for each event (#654).
  def preload_syncables(events)
    @syncables = SYNCABLE_KEYS.to_h do |key, scope|
      ids = events.filter_map { |event| event[key] }.uniq
      [ key, ids.any? ? scope.call.where(id: ids).index_by(&:id) : {} ]
    end
  end

  def resolve_syncable(event)
    key = SYNCABLE_KEYS.keys.find { |k| event[k] }
    raise "Unknown event type — missing meeting_time_id, final_exam_id, or university_calendar_event_id" unless key

    loaded = @syncables&.fetch(key)
    return loaded[event[key]] if loaded&.key?(event[key])

    SYNCABLE_KEYS[key].call.find_by(id: event[key])
  end

  def apply_preferences_to_event(syncable, course_event, preference_resolver: nil, template_renderer: nil)
    return course_event unless syncable

    resolver = preference_resolver || PreferenceResolver.new(user)
    renderer = template_renderer  || CalendarTemplateRenderer.new

    prefs = resolver.resolve_for(syncable)

    context = case syncable
    when FinalExam
                CalendarTemplateRenderer.build_context_from_final_exam(syncable)
    when UniversityCalendarEvent
                CalendarTemplateRenderer.build_context_from_university_calendar_event(syncable)
    else
                CalendarTemplateRenderer.build_context_from_meeting_time(syncable)
    end

    event_data = course_event.dup

    event_data[:summary]     = renderer.render(prefs[:title_template], context)       if prefs[:title_template].present?
    event_data[:description] = renderer.render(prefs[:description_template], context) if prefs[:description_template].present?
    event_data[:location]    = renderer.render(prefs[:location_template], context)    if prefs[:location_template].present?

    event_data[:reminder_settings] = prefs[:reminder_settings] unless prefs[:reminder_settings].nil?
    # A lowercase "#rrggbb" hex, or nil. Each provider turns it into its own
    # kind of color: a Google event label, or an Outlook category.
    event_data[:color_id]           = GoogleCalendar::Colors.normalize(prefs[:color_id])
    event_data[:visibility]         = prefs[:visibility] if prefs[:visibility].present?

    event_data
  end

  # Returns true only when the event (including its full recurrence) is entirely in the past.
  # end_time stores the *first* occurrence, so it's past for any ongoing recurring event.
  # Instead, parse the UNTIL date from the RRULE when present.
  def event_fully_past?(cal_event)
    rrule = Array(cal_event.recurrence).find { |r| r.start_with?("RRULE:") }
    if rrule
      until_match = rrule.match(/UNTIL=(\d{8}T\d{6}Z)/)
      return until_match ? Time.parse(until_match[1]).past? : false
    end

    cal_event.end_time&.past?
  end
end
