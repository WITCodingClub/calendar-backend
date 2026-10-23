# frozen_string_literal: true

module McpTools
  module Prompts
    # Plans the terms from now to graduation: which required course goes in
    # which term, in prerequisite order, in a term when it is usually offered.
    #
    # WIT Calendar has no degree requirement data yet, so the student gives
    # the list of required courses (requirements_steps). Issue #799 adds
    # requirement tools. When they ship, change requirements_steps to call
    # them, and ask the student only for what they do not give.
    class PlanDegreeProgression < BasePrompt
      prompt_name "plan_degree_progression"
      title "Plan my path to graduation"
      description "Plan the courses for each term from now to graduation, in prerequisite order and in " \
                  "the terms each course is usually offered. You give the list of required courses."
      arguments [
        MCP::Prompt::Argument.new(name: "program", title: "Program",
                                  description: "Your major or program, for example BS Computer Science."),
        MCP::Prompt::Argument.new(name: "catalog_year", title: "Catalog year",
                                  description: "The catalog year of your program, for example 2024-2025."),
        MCP::Prompt::Argument.new(name: "graduation_term", title: "Graduation term",
                                  description: "The term you want to graduate, for example Spring 2028.")
      ]

      private

      def steps
        [
          "Help me plan the courses I take in each term from now until I graduate from Wentworth Institute of " \
          "Technology. Use the WIT Calendar tools.",
          [
            fact_text("program", "Program"),
            fact_text("catalog_year", "Catalog year"),
            fact_text("graduation_term", "Graduation term")
          ].join("\n"),
          "Do these steps in this order:",
          numbered(
            "Call list_terms to get the current term and the next term.",
            "Call my_course_history to get the courses I took. The history shows only the terms that I processed " \
            "in WIT Calendar, and it shows no grades. Show me the list and ask me to correct it: courses I did not " \
            "pass, courses missing from the list, and transfer or AP credit.",
            *requirements_steps,
            "Ask me how many credits I want to take in a term, which terms I will be on co-op or not take classes, " \
            "and if I will take summer classes.",
            "For each required course that I did not complete, call get_course with the code. Read the credits, " \
            "the prerequisites, the corequisites, the restrictions, and the terms it is usually offered. Call " \
            "get_course for each prerequisite that is not on my list, too.",
            "Put each course in a term from the next term to my graduation term. A course goes after all of its " \
            "prerequisites, in the same term as its corequisites, and in a term when it is usually offered. Keep " \
            "each term at or under the credit load I gave. Put the courses at the start of a long prerequisite " \
            "chain first.",
            "For the next term only, call search_sections for each course in that term, to check that it has " \
            "sections. A later term usually has no sections yet, so use the terms each course is usually offered."
          ),
          "Show the plan as one table for each term: course, title, credits, and the prerequisites it needs. Give " \
          "the credits of each term and the total.",
          "Then list the risks: a course offered in one season only, a long prerequisite chain, a term with a heavy " \
          "load, a course with a restriction I may not meet, and a required course with no catalog data. If the " \
          "plan cannot reach my graduation term, say so and say which courses push it later.",
          "Tell me that this plan is a draft. My degree audit and my advisor decide which courses count."
        ]
      end

      # WIT Calendar has no degree requirements yet. The student gives the
      # list. Issue #799: replace these steps with the requirement tools.
      def requirements_steps
        [
          "WIT Calendar has no degree requirement data. Ask me for my program, my catalog year, and the list of " \
          "required courses that I have not completed, if I did not give them. Tell me that I can copy the list " \
          "from my degree audit or from my program page on catalog.wit.edu. Do not make up a list " \
          "of required courses.",
          "For each elective slot in my list, ask me which course I want, or leave the slot open in the plan."
        ]
      end

      def fact_text(name, label)
        value = args[name]
        value ? "#{label}: #{quoted(value)}" : "#{label}: I did not say. Ask me."
      end
    end
  end
end
