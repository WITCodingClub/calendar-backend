# frozen_string_literal: true

module McpTools
  module Prompts
    # Plans a schedule for one term: prerequisites, sections, and a check for
    # conflicts and lecture and lab pairs, then one to three options.
    class PlanTermSchedule < BasePrompt
      prompt_name "plan_term_schedule"
      title "Plan a term schedule"
      description "Plan a class schedule for one term: check prerequisites, find sections that fit your " \
                  "preferences, and get one to three schedules with no conflicts, with their CRNs."
      arguments [
        MCP::Prompt::Argument.new(name: "term", title: "Term",
                                  description: "The term uid or name, for example 202710 or Spring 2027. Default: the next term."),
        MCP::Prompt::Argument.new(name: "courses", title: "Courses",
                                  description: "The courses you want, separated by commas, for example COMP 2350, MATH 1750."),
        MCP::Prompt::Argument.new(name: "preferences", title: "Preferences",
                                  description: "For example: no classes before 10:00, Fridays off, or an instructor you want.")
      ]

      private

      def steps
        [
          "Help me plan my class schedule for one term at Wentworth Institute of Technology. Use the WIT Calendar tools.",
          [ term_text, courses_text, preferences_text ].join("\n"),
          "Do these steps in this order:",
          numbered(
            "Call list_terms to get the term_uid. Use this term_uid in every call that takes one.",
            "Call my_courses with the term_uid. If I already have courses in the term, keep them in every option.",
            "Call my_course_history to see the courses I took. The history shows only the terms that I processed " \
            "in WIT Calendar, and it shows no grades. It can have gaps.",
            "For each course I want, call get_course with the code and the term_uid. Read the prerequisites, the " \
            "corequisites, the restrictions, and the sections in the term. If my history does not show a " \
            "prerequisite, ask me if I completed it. Do not put a course in an option until its prerequisites " \
            "are met or I confirm them. Add each corequisite to the plan. If a course has no sections in the term, " \
            "tell me, and give the terms it is usually offered.",
            "For each course, call search_sections with the term_uid, the subject, and the course_number. Use my " \
            "preferences as filters: begins_after, ends_before, free_days, meets_on, and instructor. If a filter " \
            "removes every section of a course, tell me and show the sections without that filter.",
            "If I care about instructors, call get_instructor or search_reviews for the instructors of the sections " \
            "that are left.",
            "If I saved meetings with friends or have other fixed times, call my_busy_times for one typical week " \
            "of the term and keep those times free.",
            "Make one to three options. For each option, call check_schedule with the term_uid and every CRN in " \
            "the option, labs included. check_schedule gives the lecture and lab pairs from Banner: do not guess a " \
            "pair from the section numbers. Change the option and call check_schedule again until it shows no time " \
            "conflicts, no missing lecture or lab pair, and no course two times.",
            "Call university_events for the dates of the term, to give me the registration dates and the last day " \
            "to add or drop a course."
          ),
          "Show each option as a table: course, title, section, CRN, days and times, instructor, credits, and seats. " \
          "Give the total credits, and say how the option matches my preferences. Show the full CRN list of each " \
          "option, so I can copy it into LeopardWeb.",
          "Tell me that check_schedule must show no conflicts for the final set of CRNs before I register, and that " \
          "seats and times can change. WIT Calendar does not register me: I register in LeopardWeb."
        ]
      end

      def courses_text
        value = args["courses"]
        return "Courses I want: I did not name them. Ask me which courses I want or need to take." if value.nil?

        codes = course_codes
        return "Courses I want: #{quoted(value)}. Call search_courses to find each code." if codes.empty?

        "Courses I want: #{codes.join(', ')}. I wrote: #{quoted(value)}. If I named a course without a code, " \
          "call search_courses to find it."
      end

      def preferences_text
        value = args["preferences"]
        return "My preferences: I did not give any. Ask me one time about start and end times, days off, and instructors." if value.nil?

        "My preferences: #{quoted(value)}"
      end
    end
  end
end
