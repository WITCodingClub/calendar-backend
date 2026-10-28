# frozen_string_literal: true

module McpTools
  module Prompts
    # Base for every MCP prompt. A subclass sets prompt_name, title,
    # description, and arguments, and defines steps: the text of the message.
    #
    # The message is a user message, in the words of the student. It names
    # the tools to call and their order, tells the model to ask the student
    # for a fact that no tool gives, and ends with the advisor message. A
    # prompt reads no student data. The tools read it when the model calls
    # them, with the scopes of the token.
    class BasePrompt < MCP::Prompt
      # An argument is free text from the client. Longer text is cut.
      MAX_ARGUMENT_LENGTH = 500

      ASK = "Do not guess a fact that the tools do not give you, such as a course I took, a grade, my program, " \
            "or a preference. Ask me for it, then continue. When you have more than one question, ask them all at one time."

      PERMISSION = "If a tool answers that a permission is missing, tell me how to add it. Then continue with the " \
                   "tools that work, and tell me what you could not check."

      # Banner override types, and who gives them at Wentworth. The server
      # instructions say the same.
      OVERRIDE = "Banner can block a registration: a full section, a missing prerequisite or corequisite, a major, " \
                 "program, or class year restriction, a time conflict, a section that needs instructor or department " \
                 "approval, or more credits than the term maximum. I can ask for an override of the block from the " \
                 "dean's office of the school that offers the course. If a full section has a waitlist (the section " \
                 "result shows it), I can join the waitlist first. An override is not certain, so make plans that " \
                 "do not need one. Offer one option that needs an override only when no plan without one works, or " \
                 "when I am stuck or worried. For that option, name the override and the course, and for a time " \
                 "conflict give the minutes of overlap."

      ADVISOR = "WIT Calendar is not an official Wentworth service, and its data can be out of date. At the end, " \
                "tell me to confirm the plan with my program director and my academic advisor before I register, " \
                "drop a course, or change my plan."

      SEASONS = Term.seasons.keys.freeze

      # The separators of a list of course codes in the courses argument.
      # McpTools::Completions splits on the same ones.
      COURSE_SEPARATORS = /[,;\n]/

      class << self
        # The SDK calls this before template. An argument list that is not
        # an object, or a value that is not text, is a client error: it
        # answers Invalid params (-32602), not Internal error.
        def validate_arguments!(args)
          unless args.nil? || (args.is_a?(Hash) && args.values.all? { |value| value.nil? || value.is_a?(String) || value.is_a?(Numeric) })
            raise MCP::Server::RequestHandlerError.new(
              "Invalid params: arguments must be an object with string values",
              nil,
              error_type: :invalid_params,
              error_code: ::JsonRpcHandler::ErrorCode::INVALID_PARAMS
            )
          end

          super
        end

        # A term by uid (202710) or by name ("Spring 2027"), or nil.
        # McpTools::Completions uses it for the term in the completion context.
        def find_term(value)
          case value.to_s.strip
          when /\A\d{6}\z/ then Term.find_by(uid: value.to_i)
          when /\A(#{SEASONS.join('|')})\s+(\d{4})\z/io
            Term.find_by(season: ::Regexp.last_match(1).downcase, year: ::Regexp.last_match(2).to_i)
          end
        end

        # The next fall or spring term after the current term, as
        # [season, year]: the term students register for. Summer is left
        # out, because in March a student registers for fall, not summer.
        def planning_season_and_year(current = Term.current)
          return nil unless current

          current.fall? ? [ "spring", current.year + 1 ] : [ "fall", current.year ]
        end

        def template(args, server_context: nil)
          text = new(normalize(args)).text

          MCP::Prompt::Result.new(
            description: description_value,
            messages:    [ MCP::Prompt::Message.new(role: "user", content: MCP::Content::Text.new(text)) ]
          )
        end

        def argument_names = arguments_value.map { |argument| argument.name.to_s }

        private

        # String keys and values, stripped and cut, with blanks left out.
        def normalize(args)
          (args || {}).to_h.each_with_object({}) do |(name, value), result|
            value = value.to_s.strip.first(MAX_ARGUMENT_LENGTH)
            result[name.to_s] = value if value.present?
          end
        end
      end

      def initialize(args)
        @args = args
      end

      def text
        [ *steps, ASK, PERMISSION, OVERRIDE, ADVISOR ].join("\n\n")
      end

      private

      attr_reader :args

      def steps = raise(NotImplementedError)

      # Numbered steps, one a line.
      def numbered(*lines)
        lines.flatten.compact.each_with_index.map { |line, index| "#{index + 1}. #{line}" }.join("\n")
      end

      # Text from the student, in quotes, so the model reads it as data.
      def quoted(value) = "\"#{value.tr('"', "'")}\""

      # The term line. The argument is a term uid (202710) or a name
      # ("Spring 2027"). Without it, the default is the next fall or spring
      # term, and the model confirms it with the student.
      def term_text
        value = args["term"]
        return default_term_text if value.nil?

        term = self.class.find_term(value)
        return "Term: #{term.name} (term_uid #{term.uid})." if term

        "Term: I asked for #{quoted(value)}, but WIT Calendar has no term with that uid or name. " \
          "Call list_terms and ask me which term I mean."
      end

      def default_term_text
        season, year = self.class.planning_season_and_year
        unless season
          return "Term: I did not name one. Call list_terms, then ask me which term I mean before you search."
        end

        name = "#{season.capitalize} #{year}"
        term = Term.find_by(season: season, year: year)
        if term
          "Term: I did not name one. Use #{name} (term_uid #{term.uid}), the next fall or spring term, " \
            "but first ask me to confirm the term. I can mean the summer term or a later term."
        else
          "Term: I did not name one. The next fall or spring term is #{name}, but WIT Calendar has no sections " \
            "for it yet. Call list_terms, tell me that #{name} is not published yet, and ask me which term I mean."
        end
      end

      # The course codes in the courses argument, as "COMP 2350".
      def course_codes
        args["courses"].to_s.split(COURSE_SEPARATORS).filter_map do |part|
          subject, number = CatalogCourse.parse_code(part)
          "#{subject} #{number}" if subject
        end.uniq
      end
    end
  end
end
