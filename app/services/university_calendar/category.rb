# frozen_string_literal: true

module UniversityCalendar
  # The UniversityCalendarEvent category of one feed event, from its summary
  # and, when the summary says nothing, the 25Live event type. The feed has no
  # category field, so the import reads the words of the title.
  module Category
    HOLIDAY_WORDS = [
      "holiday", "thanksgiving", "offices closed", "university closed", "no class",
      "memorial day", "labor day", "independence day", "july 4",
      "presidents' day", "presidents day", "patriots' day", "patriots day",
      "veterans day", "veteran's day", "indigenous peoples", "columbus day",
      "election day", "juneteenth", "wellbeing day", "well-being day"
    ].freeze
    HOLIDAY_PATTERN = /\b(spring|winter|fall|summer)\s+(break|recess)\b|martin luther king|mlk day/

    # Checked in this order: the first match wins.
    SUMMARY_WORDS = {
      "term_dates"   => [ "classes begin", "classes end", "first day of classes", "last day of classes",
                          "semester begins", "semester ends" ],
      "study_day"    => [ "study day", "study period", "reading day", "reading period" ],
      "finals"       => [ "final exam", "finals week", "exam period", "final examinations" ],
      "graduation"   => [ "commencement", "graduation", "convocation" ],
      "registration" => [ "registration", "enrollment", "add/drop", "course selection" ],
      "deadline"     => [ "deadline", "last day to", "withdrawal", "tuition due", "grade submission",
                          "incomplete grade", "pass/fail", "grade change" ]
    }.freeze

    EVENT_TYPE_WORDS = {
      "academic"     => [ "calendar announcement" ],
      "meeting"      => [ "meeting" ],
      "exhibit"      => [ "exhibit", "showcase" ],
      "announcement" => [ "announcement" ]
    }.freeze

    FALLBACK = "campus_event"

    module_function

    def infer(summary, event_type)
      summary = summary.to_s.downcase
      return "holiday" if HOLIDAY_WORDS.any? { |word| summary.include?(word) } || summary.match?(HOLIDAY_PATTERN)

      first_match(SUMMARY_WORDS, summary) || first_match(EVENT_TYPE_WORDS, event_type.to_s.downcase) || FALLBACK
    end

    def first_match(table, text)
      table.find { |_category, words| words.any? { |word| text.include?(word) } }&.first
    end
  end
end
