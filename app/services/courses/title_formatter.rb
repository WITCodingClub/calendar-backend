# frozen_string_literal: true

module Courses
  # Writes a Banner course title in title case. Banner sends most titles in
  # capitals, for example "AGENTIC AI AND INTELLIGENT AGENTS".
  #
  # Course runs every title through this formatter with `normalizes :title`,
  # so a title is formatted once, when it is written. The formatter gives the
  # same result when it runs again on a formatted title.
  #
  #   Courses::TitleFormatter.call("CALCULUS II") # => "Calculus II"
  module TitleFormatter
    # Banner sends titles in capitals, so the formatter cannot tell an acronym
    # from a word. It writes these words in capitals. Leave out acronyms that
    # are also English words, such as IT and STEM.
    ACRONYMS = %w[AI AXP BIM BME CAD CADD GIS WWW].freeze

    ACRONYM_PATTERN = /\b(#{ACRONYMS.join("|")})\b/i
    ROMAN_NUMERAL_PATTERN = /\b(i{1,3}|iv|v|vi{1,3}|ix|x)\b/i

    # Tokens to keep exactly as Banner sends them: an acronym in parentheses
    # such as "(CAD)", dotted initials such as "U.S.", and a number with
    # letters such as "3D".
    PRESERVED_PATTERNS = [
      /\(([A-Z]{2,})\)/,
      /\b([A-Z]\.[A-Z]\.?)/,
      /\b(\d+[A-Z]+)\b/
    ].freeze

    module_function

    def call(title)
      return title if title.nil?

      result = HTMLEntities.new.decode(title.to_s)

      preserved = {}
      PRESERVED_PATTERNS.each do |pattern|
        result = result.gsub(pattern) do |match|
          key = "zzpreserved#{preserved.size}zz"
          preserved[key] = match
          key
        end
      end

      # "3 D" becomes "3D", and "a-b" becomes "a - b".
      result = result.gsub(/(\d)\s+([A-Za-z])(?=\s|$)/, '\1\2')
      result = result.gsub(/(\w)-(\w)/, '\1 - \2')

      result = result.downcase
                     .gsub(/(^|\s|-)(\w)/) { $1 + $2.upcase }
                     .gsub(/(\d)([a-z])/i) { $1 + $2.upcase }

      result = result.gsub(ROMAN_NUMERAL_PATTERN, &:upcase)
      result = result.gsub(ACRONYM_PATTERN, &:upcase)

      preserved.each { |key, val| result = result.gsub(/#{Regexp.escape(key)}/i, val) }

      result
    end
  end
end
