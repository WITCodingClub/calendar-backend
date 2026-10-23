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

      ADVISOR = "WIT Calendar is not an official Wentworth service, and its data can be out of date. At the end, " \
                "tell me to confirm the plan with my program director and my academic advisor before I register, " \
                "drop a course, or change my plan."

      SEASONS = Term.seasons.keys.freeze

      class << self
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
        [ *steps, ASK, PERMISSION, ADVISOR ].join("\n\n")
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
      # ("Spring 2027"). Without it, the default is the next term, or the
      # model asks.
      def term_text(default: :next)
        value = args["term"]
        return default_term_text(default) if value.nil?

        term = find_term(value)
        return "Term: #{term.name} (term_uid #{term.uid})." if term

        "Term: I asked for #{quoted(value)}, but WIT Calendar has no term with that uid or name. " \
          "Call list_terms and ask me which term I mean."
      end

      def default_term_text(default)
        next_term = Term.next if default == :next
        return "Term: I did not name one. Use #{next_term.name} (term_uid #{next_term.uid}), the next term." if next_term

        "Term: I did not name one. Call list_terms and use next_term_uid. If it is null, ask me which term I mean."
      end

      def find_term(value)
        case value
        when /\A\d{6}\z/ then Term.find_by(uid: value.to_i)
        when /\A(#{SEASONS.join('|')})\s+(\d{4})\z/io then Term.find_by(season: ::Regexp.last_match(1).downcase, year: ::Regexp.last_match(2).to_i)
        end
      end

      # The course codes in the courses argument, as "COMP 2350".
      def course_codes
        args["courses"].to_s.split(/[,;\n]/).filter_map do |part|
          subject, number = CatalogCourse.parse_code(part)
          "#{subject} #{number}" if subject
        end.uniq
      end
    end
  end
end
