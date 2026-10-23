# frozen_string_literal: true

module McpTools
  module Prompts
    # Finds sections that fit the student's free time in one term.
    class FindClassForFreeTime < BasePrompt
      prompt_name "find_class_for_free_time"
      title "Find a class for my free time"
      description "Find sections that fit the free time in your schedule for one term, " \
                  "optionally in one subject or on given days and times."
      arguments [
        MCP::Prompt::Argument.new(name: "term", title: "Term",
                                  description: "The term uid or name, for example 202710 or Spring 2027. Default: the next term."),
        MCP::Prompt::Argument.new(name: "subject", title: "Subject",
                                  description: "A subject code, for example COMP or MATH."),
        MCP::Prompt::Argument.new(name: "days", title: "Days",
                                  description: "The days you are free, for example Tuesday and Thursday."),
        MCP::Prompt::Argument.new(name: "times", title: "Times",
                                  description: "The times you are free, for example after 13:00.")
      ]

      private

      def steps
        [
          "Find a class that fits my free time in one term at Wentworth Institute of Technology. Use the WIT Calendar tools.",
          [ term_text, subject_text, free_text("days", "Days"), free_text("times", "Times") ].join("\n"),
          "Do these steps in this order:",
          numbered(
            "Call list_terms to get the term_uid and the dates of the term.",
            "Call my_courses with the term_uid to get my classes and their CRNs.",
            "Call my_busy_times for one full week of the term, after the first week of classes. It gives my " \
            "classes, my final exams, and the meetings I saved with friends.",
            "Find the times I am free: the days and times I gave, less my busy times.",
            "Call search_sections with the term_uid and the filters that match my free time: meets_on, free_days, " \
            "begins_after, and ends_before. Add the subject if I gave one. If I gave no subject, ask me what kind " \
            "of class I want, or use q with semantic set to true for the topic I describe.",
            "For the sections that fit, call get_course to check the prerequisites and restrictions against " \
            "my_course_history. If my history does not show a prerequisite, ask me if I completed it.",
            "For each section you suggest, call check_schedule with the term_uid, my CRNs, and the new CRNs, labs " \
            "included. Suggest a section only when check_schedule shows no conflict and no missing lecture or lab pair."
          ),
          "Show up to five sections as a table: course, title, CRN, days and times, instructor, credits, and seats. " \
          "Say which prerequisites I must confirm."
        ]
      end

      def subject_text
        value = args["subject"]
        value ? "Subject: #{quoted(value)}. Call list_subjects if it is not a subject code." : "Subject: any."
      end

      def free_text(name, label)
        value = args[name]
        value ? "#{label} I am free: #{quoted(value)}" : "#{label} I am free: I did not say. Use the free times in my schedule."
      end
    end
  end
end
