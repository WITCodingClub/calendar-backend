# frozen_string_literal: true

# The Banner term code (uid) and its arithmetic. A code is the year of the
# academic year that ends in it, times 100, plus 10 (fall), 20 (spring), or 30
# (summer). So a fall term has the next year: Fall 2025 is 202610 and Spring
# 2026 is 202620. A catalog year starts in the fall, so Fall 2025, Spring 2026,
# and Summer 2026 are all in the 2025-2026 catalog.
#
# The terms table starts at the first term the catalog import saw, and a
# catalog term can be older, so this module does not read it.
module TermCode
  SEASON_SUFFIXES = { "fall" => 10, "spring" => 20, "summer" => 30 }.freeze
  # A term name in a text, such as "Fall 2025": the season and the year.
  LABEL_TEXT = /(fall|spring|summer)\s+(\d{4})/i
  LABEL = /\A#{LABEL_TEXT}\z/
  CODE  = /\A\d{4}(10|20|30)\z/

  # Banner starts long after this year. A later year than a few years from
  # now is a typo.
  FIRST_YEAR = 2000
  YEARS_AHEAD = 3

  module_function

  # The code of a label ("Fall 2025") or of a code (202610 or "202610"), or
  # nil when the value is neither, or its year is out of range. Use it for
  # what a person typed.
  def parse(value)
    code = read(value)
    code if code && (FIRST_YEAR..(Time.zone.today.year + YEARS_AHEAD)).cover?(code / 100)
  end

  # parse with no year range, for a value that only has to name a stored
  # term.
  def read(value)
    text = value.to_s.strip
    if text.match?(CODE)
      Integer(text, 10)
    elsif (match = text.match(LABEL))
      self.for(Integer(match[2], 10), match[1])
    end
  end

  # The code of a season ("fall", :spring) of a calendar year, as Term#year
  # stores it: Fall 2026 is 202710. nil for another season.
  def for(year, season)
    season = season.to_s.downcase
    suffix = SEASON_SUFFIXES[season]
    return nil if suffix.nil?

    ((season == "fall" ? year + 1 : year) * 100) + suffix
  end

  # The first season that a text names, in the order fall, spring, summer:
  # "fall" for "Fall Semester 2026". nil when it names none.
  def season_in(text)
    text = text.to_s.downcase
    SEASON_SUFFIXES.keys.find { |season| text.include?(season) }
  end

  # The code of the term that a date is in by its month: spring to May,
  # summer in June and July, fall from August.
  def for_date(date)
    season = if date.month >= 8 then "fall"
    elsif date.month >= 6 then "summer"
    else "spring"
    end
    self.for(date.year, season)
  end

  # { year:, season: } of a code, with the calendar year (202710 is fall
  # 2026), or nil for a value that is not a code.
  def year_and_season(code)
    return nil unless code.to_s.match?(CODE)

    code = code.to_i
    season = season(code)
    { year: season == "fall" ? (code / 100) - 1 : code / 100, season: season.to_sym }
  end

  def label(code)
    parts = year_and_season(code)
    parts && "#{parts[:season].capitalize} #{parts[:year]}"
  end

  def season(code) = SEASON_SUFFIXES.key(code % 100)

  def summer?(code) = season(code) == "summer"

  # The term after a term: fall, spring, summer, fall.
  def next_term(code)
    summer?(code) ? ((code / 100) + 1) * 100 + SEASON_SUFFIXES.fetch("fall") : code + 10
  end

  # The next fall or spring term. A summer term is optional, and students
  # register for fall in the spring term, so it skips summer.
  def next_regular_term(code)
    season(code) == "fall" ? code + 10 : ((code / 100) + 1) * 100 + SEASON_SUFFIXES.fetch("fall")
  end

  # The first year of the catalog year of a term: 2025 for 202610, 202620,
  # and 202630.
  def catalog_start_year(code)
    return nil if code.nil?

    (code / 100) - 1
  end

  # The codes of the fall, spring, and summer terms of a catalog year.
  def catalog_year_codes(start_year)
    SEASON_SUFFIXES.values.map { |suffix| ((start_year + 1) * 100) + suffix }
  end

  # The catalog year of a term, such as "2025-2026".
  def catalog_year(code)
    start_year = catalog_start_year(code)
    start_year && catalog_year_name(start_year)
  end

  def catalog_year_name(start_year) = "#{start_year}-#{start_year + 1}"

  # The code of a semester of a plan of study ("Year 3, fall") for a
  # program that started in start, or nil. Year 1 is the academic year of
  # the start term, so a Spring 2026 start puts "Year 1, fall" in Fall 2025.
  # A summer start is the end of an academic year, so year 1 is the academic
  # year after it: Summer 2026 puts "Year 1, fall" in Fall 2026.
  def plan_term(start, year_index, season)
    suffix = SEASON_SUFFIXES[season.to_s]
    return nil if start.nil? || suffix.nil? || year_index.nil?

    ((first_plan_year(start) + year_index - 1) * 100) + suffix
  end

  # The plan year of a term for a program that started in start, the
  # inverse of plan_term: a summer term after year 1 is in year 1. nil for a
  # term before year 1, such as a course taken before the program started.
  def plan_year(start, code)
    year = (code / 100) - first_plan_year(start) + 1
    year.positive? ? year : nil
  end

  def first_plan_year(start)
    summer?(start) ? (start / 100) + 1 : start / 100
  end
  private_class_method :first_plan_year
end
