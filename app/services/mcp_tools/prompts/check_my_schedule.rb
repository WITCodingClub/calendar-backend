# frozen_string_literal: true

module McpTools
  module Prompts
    # Checks the student's own schedule in one term: conflicts, lecture and
    # lab pairs, corequisites, and final exams.
    class CheckMySchedule < BasePrompt
      prompt_name "check_my_schedule"
      title "Check my schedule"
      description "Check your courses in one term for time conflicts, missing lecture and lab pairs, " \
                  "missing corequisites, and final exams on the same day."
      arguments [
        MCP::Prompt::Argument.new(name: "term", title: "Term",
                                  description: "The term uid or name, for example 202710 or Spring 2027. " \
                                               "Default: the next term if you have courses in it, else the current term.")
      ]

      private

      def steps
        [
          "Check my class schedule for one term at Wentworth Institute of Technology. Use the WIT Calendar tools.",
          args["term"] ? term_text : "Term: I did not name one. Call list_terms, then call my_courses with " \
                                     "next_term_uid. If I have no courses in that term, use current_term_uid. " \
                                     "Tell me which term you checked.",
          "Do these steps in this order:",
          numbered(
            "Call my_courses with the term_uid. If the list is empty, tell me that WIT Calendar has no courses " \
            "for me in that term, and that I must process the term in the WIT Calendar extension. Then stop.",
            "Call check_schedule with the term_uid and the CRN of every course from my_courses, labs included.",
            "Report each time conflict, each lecture or lab that is missing its linked pair, and each course that " \
            "is in the schedule two times. For a missing pair, call search_sections to find the sections that " \
            "complete it, and call check_schedule again with them before you suggest one.",
            "For each course, call get_course with the code. If a corequisite is not in the schedule and is not " \
            "in my_course_history, tell me.",
            "Call my_finals with the term_uid. Report two exams at the same time, and days with more than two " \
            "exams. If the list is empty, the finals schedule can be not published yet: the advisory says when " \
            "WIT Calendar last read it."
          ),
          "Give the totals from check_schedule: credits, days on campus, earliest start, and latest end. If you " \
          "find no problem, say so. Do not change my schedule: suggest changes only."
        ]
      end
    end
  end
end
