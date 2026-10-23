# frozen_string_literal: true

module McpTools
  # Answers completion/complete for the prompt arguments (docs/mcp.md).
  # The values are public catalog data, the same for every student.
  #
  # - term: term uids, the current and future terms first, then the past
  #   terms, newest first. The value matches the start of the uid or the name.
  # - subject: subject codes with active sections, in the term of the term
  #   argument when the client sends it, else in the current and future terms.
  # - courses: course codes from the catalog. The argument is a list, so only
  #   the part after the last separator (comma, semicolon, or new line)
  #   completes.
  #
  # Each match is on the start of the value and ignores case. An argument
  # that the prompt does not have, or that has no completions, gets no values.
  class Completions
    # The most values that the spec allows in one answer.
    LIMIT = 100

    def self.call(params) = new(params).call

    def initialize(params)
      @params = params.is_a?(Hash) ? params : {}
    end

    def call
      values = values_for(argument_name, argument_value)
      { completion: { values: values.first(LIMIT), hasMore: values.size > LIMIT } }
    end

    private

    attr_reader :params

    def values_for(name, value)
      return [] unless dig(:ref, :type) == "ref/prompt"

      prompt = Prompts.find(dig(:ref, :name))
      return [] unless prompt&.argument_names&.include?(name)

      case name
      when "term"    then terms(value)
      when "subject" then subjects(value)
      when "courses" then courses(value)
      else []
      end
    end

    def argument_name  = dig(:argument, :name).to_s
    def argument_value = dig(:argument, :value).to_s

    # Hash#dig raises when a client sends text or a list where the spec has
    # an object. Such a part counts as missing.
    def dig(*keys)
      keys.reduce(params) { |node, key| node.is_a?(Hash) ? node[key] : nil }
    end

    def terms(value)
      needle = value.strip.downcase
      all = Term.reverse_chronological.to_a
      upcoming = Term.current_and_future.to_a.reverse
      (upcoming + (all - upcoming)).select do |term|
        term.uid.to_s.start_with?(needle) || term.name.downcase.start_with?(needle)
      end.map { |term| term.uid.to_s }
    end

    def subjects(value)
      needle = value.strip.upcase
      Catalog::SubjectQuery.new.codes(term_uids: subject_term_uids).select { |code| code.upcase.start_with?(needle) }
    end

    # The term the client already filled in (a uid or a name, the same as the
    # prompts take). Without one, the current and future terms, so the query
    # does not read every past term. Without those, every term.
    def subject_term_uids
      context = dig(:context, :arguments, :term)
      term = Prompts::BasePrompt.find_term(context) if context.is_a?(String) || context.is_a?(Numeric)
      return [ term.uid ] if term

      uids = Term.current_and_future.pluck(:uid)
      uids.presence
    end

    # Only the code after the last separator completes. The text before it
    # stays, with one space after the separator.
    # One more than the limit, so hasMore is true when there are more.
    def courses(value)
      parts  = value.split(/(#{Prompts::BasePrompt::COURSE_SEPARATORS})/o)
      last   = parts.last.to_s.match?(Prompts::BasePrompt::COURSE_SEPARATORS) ? "" : parts.pop.to_s
      head   = parts.join.sub(/[ \t]+\z/, "")
      prefix = head.empty? ? "" : "#{head}#{' ' unless head.end_with?("\n")}"
      Catalog::CourseQuery.new.codes_starting_with(last, limit: LIMIT + 1).map { |code| "#{prefix}#{code}" }
    end
  end
end
