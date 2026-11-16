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

    # "finals" cancels classes, so it is an allowlist: only a title that
    # names the exam period gets it. "Final Exam Schedule ..." and "Final Exam
    # Conflict ..." do not, even with "(" or a word after them.
    FINALS_PERIOD_PATTERN = /
      final\s+exam\s+period | finals\s+week | exam(?:ination)?\s+period | final\s+examinations |
      final\s+exams?(?!\s+(?:schedule|conflict))(?:\s|\(|$)
    /x

    # A title with a finals word that does not name the exam period.
    NOT_A_PERIOD_DEADLINE_PATTERN = /\b(?:due|submit|request)/

    module_function

    def infer(summary, event_type)
      summary = summary.to_s.downcase
      return "holiday" if HOLIDAY_WORDS.any? { |word| summary.include?(word) } || summary.match?(HOLIDAY_PATTERN)

      category = first_match(SUMMARY_WORDS, summary)
      category = finals_word_category(summary) if category == "finals"

      category || first_match(EVENT_TYPE_WORDS, event_type.to_s.downcase) || FALLBACK
    end

    # True when the title names a final exam period, the only finals title
    # that cancels classes. TermDates reads the same rule.
    def finals_period?(summary)
      summary.to_s.downcase.match?(FINALS_PERIOD_PATTERN)
    end

    # The category of a title with a finals word: finals for an exam period,
    # deadline for a deadline or a request, and academic for any other
    # announcement, such as "Final Exam Schedule Available to Students".
    def finals_word_category(summary)
      return "finals" if finals_period?(summary)
      return "deadline" if summary.match?(NOT_A_PERIOD_DEADLINE_PATTERN) || SUMMARY_WORDS["deadline"].any? { |word| summary.include?(word) }

      "academic"
    end

    def first_match(table, text)
      table.find { |_category, words| words.any? { |word| text.include?(word) } }&.first
    end
  end
end
