# frozen_string_literal: true

module DegreeRequirements
  # Splits one course description from the course search into its parts. The
  # catalog prints it as one paragraph:
  #
  #   "Topics include ... <em><strong>Prerequisites:</strong> COMP2000 (4 credits) fall, spring</em>"
  class CourseDescriptionParser
    require "nokogiri"

    Result = Data.define(:description, :prerequisite_text, :min_credits, :max_credits, :typically_offered)

    CREDITS = /\((\d+)(?:\s*(?:-|to|or)\s*(\d+))?\s+credits?\)/i
    PREREQUISITE = /\bprerequisites?\s*:/i
    SEASONS = %w[fall spring summer].freeze

    def self.call(html) = new(html).call

    def initialize(html)
      @text = Nokogiri::HTML.fragment(html.to_s).text.gsub(/[[:space:]]+/, " ").strip
    end

    def call
      credit_match = last_match(CREDITS)
      before_credits = credit_match ? @text[0...credit_match.begin(0)] : @text
      after_credits = credit_match ? @text[credit_match.end(0)..] : ""

      description, prerequisite = before_credits.split(PREREQUISITE, 2).map(&:strip)
      Result.new(description: description.presence,
                 prerequisite_text: prerequisite.presence,
                 min_credits: credit_match && credit_match[1].to_i,
                 max_credits: credit_match && (credit_match[2] || credit_match[1]).to_i,
                 typically_offered: SEASONS.select { |season| after_credits.match?(/\b#{season}\b/i) })
    end

    private

    # The credits are the last "(N credits)" in the text. An earlier one can
    # be in the prerequisite text.
    def last_match(pattern)
      matches = []
      @text.scan(pattern) { matches << Regexp.last_match }
      matches.last
    end
  end
end
