# frozen_string_literal: true

module Preferences
  # Shapes one event hash with the person's preferences: the title,
  # description and location templates, the reminders, the color, and the
  # visibility. One instance serves one sync, so the resolver and the template
  # renderer load the person's rows once.
  class Applier
    def initialize(user, resolver: Resolver.new(user), renderer: TemplateRenderer.new(user_id: user.id))
      @resolver = resolver
      @renderer = renderer
    end

    # syncable is the record the event comes from: a Course::MeetingTime, a
    # FinalExam, or a UniversityCalendarEvent. Without one, the event stays
    # as it is.
    def apply(syncable, event)
      return event unless syncable

      prefs   = resolver.resolve_for(syncable)
      context = context_for(syncable)
      data    = event.dup

      data[:summary]     = renderer.render(prefs[:title_template], context)       if prefs[:title_template].present?
      data[:description] = renderer.render(prefs[:description_template], context) if prefs[:description_template].present?
      data[:location]    = renderer.render(prefs[:location_template], context)    if prefs[:location_template].present?

      data[:reminder_settings] = prefs[:reminder_settings] unless prefs[:reminder_settings].nil?
      # A lowercase "#rrggbb" hex, or nil. Each provider turns it into its own
      # kind of color: a Google event label, or an Outlook category.
      data[:color_id]   = Colors.normalize(prefs[:color_id])
      data[:visibility] = prefs[:visibility] if prefs[:visibility].present?

      data
    end

    private

    attr_reader :resolver, :renderer

    def context_for(syncable)
      case syncable
      when FinalExam               then TemplateRenderer.build_context_from_final_exam(syncable)
      when UniversityCalendarEvent then TemplateRenderer.build_context_from_university_calendar_event(syncable)
      else                              TemplateRenderer.build_context_from_meeting_time(syncable)
      end
    end
  end
end
