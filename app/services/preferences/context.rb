# frozen_string_literal: true

module Preferences
  # One kind of event as the preference layer sees it: the variables its
  # templates read, and the value of a preference field that no row sets.
  # MeetingTimeContext, FinalExamContext, and UniversityEventContext are the
  # kinds. Context.for picks the kind of a record.
  class Context
    def self.for(record)
      case record
      when Course::MeetingTime     then MeetingTimeContext.new(record)
      when ::FinalExam             then FinalExamContext.new(record)
      when UniversityCalendarEvent then UniversityEventContext.new(record)
      when CalendarEvent           then self.for(record.meeting_time || record.final_exam || record.university_calendar_event)
      end
    end

    attr_reader :record

    def initialize(record)
      @record = record
    end

    # The template variables (TemplateRenderer::ALLOWED_VARIABLES) and their values.
    def variables = raise(NotImplementedError)

    # The event type a CalendarPreference with scope event_type names, or nil.
    def event_type = nil

    # The category for a uni_cal_category preference, for a university event.
    def university_category = nil

    def university_event? = false

    # The value of a field that no preference row sets. config is the
    # person's UserExtensionConfig, or nil.
    def default(field, _config) = self.class::DEFAULTS[field]
  end
end
