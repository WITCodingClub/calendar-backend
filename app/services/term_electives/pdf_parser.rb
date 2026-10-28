# frozen_string_literal: true

module TermElectives
  # Reads the text of one elective list PDF (`pdftotext -layout`). Each
  # school uses its own layout: bulleted lists for each program, a table by
  # area, a table of CRNs, or course descriptions. So the parser does not
  # read the layout. It finds each course code and the nearest heading above
  # it.
  class PdfParser
    Result = Data.define(:title, :season, :year, :courses)
    Course = Data.define(:subject_code, :course_number, :heading)

    # "COMP2000", "ECON 4102", "ARCH3800-02".
    CODE = /\b([A-Z]{4}) ?(\d{4})\b/
    # "Economics (ECON)      4102" in a table with a subject column.
    PAREN_CODE = /\(([A-Z]{4})\)\s+(\d{4})\b/
    TERM = /\b(spring|summer|fall)\s+(\d{4})\b/i
    # The header row of a table, such as "Area  Course  Title  Course Times".
    COLUMN_HEADER = /\bcourse\b.*\btitle\b/i
    TERM_LINES = 8
    MAX_HEADING_WORDS = 12
    MAX_HEADING_LENGTH = 80
    MAX_HEADING_INDENT = 2
    MAX_LINE_ABOVE_HEADING = 70

    def self.parse(text)
      new(text).parse
    end

    def initialize(text)
      @lines = text.to_s.lines.map { |line| line.chomp.tr("\f", "") }
    end

    def parse
      season, year = term
      Result.new(title: title, season: season, year: year, courses: courses)
    end

    private

    def title
      @lines.map { |line| squish(line) }.find(&:present?)
    end

    # The season and year in the first lines of the text, where the title
    # is. A file name can name another term than the text: "SP26 ARCH
    # Undergrad Electives.pdf" is for Spring 2027. The body can name other
    # terms, such as "for students who took it in Fall 2026", so a term
    # further down is not read, and a title with two terms gives none.
    def term
      top = @lines.reject { |line| line.strip.empty? }.first(TERM_LINES).join("\n")
      terms = top.scan(TERM).map { |season, year| [ season.downcase, year.to_i ] }.uniq
      terms.first if terms.one?
    end

    def courses
      heading = nil
      found = []

      @lines.each_with_index do |line, index|
        codes = codes_in(line)
        if codes.any?
          codes.each { |subject, number| found << Course.new(subject, number, heading) }
        elsif heading_at?(index)
          heading = squish(line).delete_suffix(":").strip
        end
      end

      found.uniq
    end

    # A heading stands alone: the line above it is blank or short, so it is
    # not the end of a paragraph, and the next line of content is a course
    # or another heading.
    def heading_at?(index)
      return false unless heading_text?(@lines[index])

      previous = index.zero? ? "" : squish(@lines[index - 1])
      return false if previous.length > MAX_LINE_ABOVE_HEADING

      following = next_content_line(index)
      following.present? && (codes_in(following).any? || heading_text?(following))
    end

    # Skips blank lines, column headers, and indented lines with no course
    # code, such as the meeting times in a table row.
    def next_content_line(index)
      @lines.drop(index + 1).find do |line|
        next false if line.strip.empty? || line.match?(COLUMN_HEADER)

        codes_in(line).any? || indent(line) <= MAX_HEADING_INDENT
      end
    end

    def codes_in(line)
      pairs = line.scan(PAREN_CODE).presence || line.scan(CODE)
      pairs.map { |subject, number| [ subject, number.to_i ] }
    end

    # A heading is a short line at the left margin with no digits that is
    # not a sentence or a list of subjects, such as "Computer Science
    # Elective" or "Lab-based Science Electives (BSCN, BCOS, BSCY, BSDS,
    # BSIT)". A line further right is a cell of a table row.
    def heading_text?(line)
      text = squish(line)
      return false if indent(line) > MAX_HEADING_INDENT || !text.match?(/\A[[:alpha:]]/)
      return false if text.match?(/\d/) || text.match?(/[.,;]\z/) || text.match?(COLUMN_HEADER)
      return false if text.gsub(/\([^)]*\)/, "").count(",") > 1

      text.length <= MAX_HEADING_LENGTH && text.split.size <= MAX_HEADING_WORDS
    end

    def indent(line)
      line[/\A */].size
    end

    def squish(line)
      line.gsub(/\s+/, " ").strip
    end
  end
end
