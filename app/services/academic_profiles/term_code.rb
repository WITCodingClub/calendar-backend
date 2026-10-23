# frozen_string_literal: true

module AcademicProfiles
  # Converts between a term label as LeopardWeb shows it ("Fall 2025") and a
  # Banner term code (202610). A Banner code names the academic year that ends
  # in the year of the code, so a fall term has the next year: Fall 2025 is
  # 202610 and Spring 2026 is 202620.
  #
  # The terms table starts at the first term the catalog import saw, and a
  # catalog term can be older, so this module does not read it.
  module TermCode
    SEASON_SUFFIXES = { "fall" => 10, "spring" => 20, "summer" => 30 }.freeze
    LABEL = /\A(fall|spring|summer)\s+(\d{4})\z/i
    CODE  = /\A\d{4}(10|20|30)\z/

    module_function

    # Banner starts long after this year. A later year than a few years from
    # now is a typo.
    FIRST_YEAR = 2000
    YEARS_AHEAD = 3

    # Returns the Banner code for a label or a code, or nil when the value is
    # neither, or its year is out of range.
    def parse(value)
      text = value.to_s.strip
      code = if text.match?(CODE)
        Integer(text, 10)
      elsif (match = text.match(LABEL))
        season = match[1].downcase
        year = Integer(match[2], 10)
        year += 1 if season == "fall"
        (year * 100) + SEASON_SUFFIXES.fetch(season)
      end

      code if code && (FIRST_YEAR..(Time.zone.today.year + YEARS_AHEAD)).cover?(code / 100)
    end

    def label(code)
      return nil if code.nil?

      season = SEASON_SUFFIXES.key(code % 100)
      year = code / 100
      year -= 1 if season == "fall"
      "#{season.capitalize} #{year}"
    end

    # The catalog year of a term, for example "2025-2026" for Fall 2025,
    # Spring 2026, and Summer 2026. A catalog year starts in the fall.
    def catalog_year(code)
      return nil if code.nil?

      start_year = (code / 100) - 1
      "#{start_year}-#{start_year + 1}"
    end
  end
end
