# frozen_string_literal: true

module McpTools
  # Answers completion/complete for the prompt arguments (docs/mcp.md).
  # The values are public catalog data, the same for every student.
  #
  # - term: term uids, the current and future terms first, then the past
  #   terms, newest first. The value matches the start of the uid or the name.
  # - subject: subject codes with active sections, in the term of the term
  #   argument when the client sends it.
  # - courses: course codes from the catalog. The argument is a list, so only
  #   the part after the last comma completes.
  #
  # Each match is on the start of the value and ignores case. An argument
  # that the prompt does not have, or that has no completions, gets no values.
  class Completions
    # The most values that the spec allows in one answer.
    LIMIT = 100

    def self.call(params) = new(params).call

    def initialize(params)
      @params = params || {}
    end

    def call
      values = values_for(argument_name, argument_value)
      { completion: { values: values.first(LIMIT), hasMore: values.size > LIMIT } }
    end

    private

    attr_reader :params

    def values_for(name, value)
      return [] unless params.dig(:ref, :type) == "ref/prompt"

      prompt = Prompts.find(params.dig(:ref, :name))
      return [] unless prompt&.argument_names&.include?(name)

      case name
      when "term"    then terms(value)
      when "subject" then subjects(value)
      when "courses" then courses(value)
      else []
      end
    end

    def argument_name  = params.dig(:argument, :name).to_s
    def argument_value = params.dig(:argument, :value).to_s

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
      Catalog::SubjectQuery.new.codes(term_uid: context_term_uid).select { |code| code.upcase.start_with?(needle) }
    end

    # One more than the limit, so hasMore is true when there are more.
    def courses(value)
      head, _, last = value.rpartition(",")
      prefix = head.strip.empty? ? "" : "#{head.strip}, "
      Catalog::CourseQuery.new.codes_starting_with(last, limit: LIMIT + 1).map { |code| "#{prefix}#{code}" }
    end

    # The term argument the client already filled in, when it is a uid.
    def context_term_uid
      uid = params.dig(:context, :arguments, :term).to_s.strip
      uid if uid.match?(/\A\d{6}\z/)
    end
  end
end
