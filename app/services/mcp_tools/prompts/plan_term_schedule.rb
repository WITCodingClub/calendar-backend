# frozen_string_literal: true

module McpTools
  module Prompts
    # Plans a schedule for one term: prerequisites, then find_schedules for
    # the schedules with no conflicts and with their lecture and lab pairs,
    # then one to three options.
    class PlanTermSchedule < BasePrompt
      # How registration works at Wentworth, from the Registrar's notice for
      # Spring 2027. The server instructions say the same.
      REGISTRATION = "Then tell me what to do before I register. My registration time is on my time ticket, in " \
                     "myWentworth under Prepare for Registration. It comes from my completed earned credits, with " \
                     "transfer and graduate credits, but not credits in progress. If I am a first-year student or a " \
                     "sophomore, or I am on academic probation, continued probation, or academic dismissal, I need a " \
                     "Registration Alternate PIN (RAC) from my primary advisor before I can register. Do not guess my " \
                     "class year or my standing: if you do not know them, tell me the RAC rule. Call list_term_electives to " \
                     "see the Technical, Major, and HSS elective lists that the schools sent for the term. If a " \
                     "Technical or HSS elective that I need is not in the schedule yet, tell me to ask the dean or " \
                     "associate dean of my school."

      prompt_name "plan_term_schedule"
      title "Plan a term schedule"
      description "Plan a class schedule for one term: check prerequisites, find sections that fit your " \
                  "preferences, and get one to three schedules with no conflicts, with their CRNs."
      arguments [
        MCP::Prompt::Argument.new(name: "term", title: "Term",
                                  description: "The term uid or name, for example 202710 or Spring 2027. Default: the next fall or spring term."),
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
            "prerequisite, ask me if I completed it. If a prerequisite has a min_grade, ask me for my grade, because " \
            "my history has no grades. Do not put a course in an option until its prerequisites " \
            "are met or I confirm them. Add each corequisite to the plan. If a course has no sections in the term, " \
            "tell me, and give the terms it is usually offered.",
            "Call find_schedules with the term_uid and one course entry for each course I want. If I may take " \
            "one of several courses, such as an elective, put their codes in one entry. Add one entry for each " \
            "course I already have from my_courses, with its code and its CRNs in crns, so every schedule keeps " \
            "it. Give my preferences as hard " \
            "rules only when I said that I must have them: blocked, earliest, latest, day_off, and open_only. Give " \
            "the others as soft rules: avoid, days, and breaks. find_schedules gives the lecture and lab pairs from " \
            "Banner: do not guess a pair from the section numbers. If count is 0, show me the relax list and ask " \
            "me which preference to drop, then call find_schedules again. If not_offered lists a course, tell me, " \
            "and give the terms it is usually offered.",
            "If I care about instructors, call get_section for the CRNs of the best schedules, then get_instructor " \
            "or search_reviews for their instructors.",
            "If I saved meetings with friends or have other fixed times, call my_busy_times for one typical week " \
            "of the term, and call find_schedules again with those times in blocked.",
            "Pick one to three options from the schedules. Call check_schedule with the term_uid and every CRN of " \
            "each option, labs included, to show me its totals and to confirm it has no conflicts.",
            "Call university_events for the dates of the term, to give me the registration dates and the last day " \
            "to add or drop a course."
          ),
          "Show each option as a table: course, title, section, CRN, days and times, instructor, credits, and seats. " \
          "Give the total credits, and say how the option matches my preferences. Show the full CRN list of each " \
          "option, so I can copy it into LeopardWeb.",
          "Tell me that check_schedule must show no conflicts for the final set of CRNs before I register, unless I " \
          "have a time conflict override, and that seats and times can change. WIT Calendar does not register me: I register in LeopardWeb.",
          REGISTRATION
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
