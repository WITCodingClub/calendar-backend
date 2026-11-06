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
    # are also English words, such as IT, STEM, BE and US.
    ACRONYMS = %w[
      AI AXP BIM BME CAD CADD CAM CE CIS CM FM GIS ML MSBA SCDS SOM SSH TCAD TPMC UI UX WWW
      BBME BCET BCOS BCOT BCTS BEET BELM BFPM BIND BINT BMET BPM BPS
    ].freeze

    # Degree program codes such as BSCE and BSEE, which co-op and lab titles
    # list: "Engr Laboratory - BSCE/BSEN".
    PROGRAM_CODE = "BS[A-Z]{1,3}"

    ACRONYM_PATTERN = /\b(#{ACRONYMS.join("|")}|#{PROGRAM_CODE})\b/i
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

      # Some Banner titles hold an HTML line break: "Intro To Design<br>BSCE/BSEN".
      result = decode_entities(title.to_s).gsub(/\s*<br\s*\/?>\s*/i, " - ")

      preserved = {}
      PRESERVED_PATTERNS.each do |pattern|
        result = result.gsub(pattern) do |match|
          key = "zzpreserved#{preserved.size}zz"
          preserved[key] = match
          key
        end
      end

      # "3 D" becomes "3D". A hyphen stays as Banner sends it: "CO-OP" becomes
      # "Co-Op", and "DESIGN - LAB" keeps its spaces.
      result = result.gsub(/(\d)\s+([A-Za-z])(?=\s|$)/, '\1\2')

      result = result.downcase
                     .gsub(%r{(^|[\s\-/(])(\w)}) { $1 + $2.upcase }
                     .gsub(/(\d)([a-z])/i) { $1 + $2.upcase }

      result = result.gsub(ROMAN_NUMERAL_PATTERN, &:upcase)
      result = result.gsub(ACRONYM_PATTERN, &:upcase)

      preserved.each { |key, val| result = result.gsub(/#{Regexp.escape(key)}/i, val) }

      result
    end

    # Banner sometimes encodes an entity twice ("&amp;amp;"). Decode until the
    # text stops changing, so a second pass has nothing left to decode.
    def decode_entities(text)
      decoder = HTMLEntities.new
      3.times do
        decoded = decoder.decode(text)
        return decoded if decoded == text

        text = decoded
      end
      text
    end
  end
end
