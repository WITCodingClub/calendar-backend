# frozen_string_literal: true

module DegreeRequirements
  # Reads the plans of study of the 2013-2014 to 2015-2016 catalogs. Each
  # plan is a grid with a column for each semester:
  #
  #                     COMPUTER SCIENCE (BCOS)
  #                Fall Semester        Spring Semester      Summer Semester
  #       Course             Credits   Course       Credits   Course     Credits
  #       COMP1000                4    COMP1050          4
  #       Computer Science I           Computer Science II
  #   Freshman Year
  #       TOTAL CREDITS          16                     16
  #
  # A row is a code and credits, then one or more lines of title. A line of
  # totals ends each year. The year label sits in the left margin.
  #
  # A plan is left out when a year label does not count up from the first
  # year, when one year has two labels (a line of totals is missing), or when
  # a cell does not read as a course, a choice, or a placeholder. A semester
  # whose credits do not add up to its printed total only gets a warning:
  # the catalogs have such typos.
  class PdfGridParser
    HEADER = /\bFall Semester\s+Spring Semester\b/
    COURSE_COLUMN = /\bCourse\b/
    FOOTER = /\d{4}-\d{4} Academic Catalog\b/
    YEAR_LABEL = /\A(Freshman|Sophomore|Junior|Senior|Fifth|First|Second|Third|Fourth)\s+Year\z/i
    TOTALS = /\A(?:TOTAL CREDITS\s*)?(?:\d{1,2}(?:\s+|\z))+\z/
    # How far left of its column a cell may start. The PDF export moves
    # some cells by a character or two.
    SLACK = 3

    class Invalid < StandardError; end

    Cell = Data.define(:text, :start)
    Row = Struct.new(:cell, :credits, :title_lines)

    def self.call(text) = new(text).call

    def initialize(text)
      @lines = text.to_s.lines(chomp: true)
    end

    def call
      plans = []
      rejections = []
      index = 0
      while index < @lines.size
        if @lines[index].match?(HEADER)
          heading = heading_before(index)
          begin
            plan, index = parse_plan(index, heading)
            plans << plan
          rescue Invalid => e
            rejections << PdfCatalog::Rejection.new(heading: heading, line: index + 1, reason: e.message)
            index += 1
          end
        else
          index += 1
        end
      end
      PdfCatalog::Result.new(plans: plans, rejections: rejections)
    end

    private

    # The program name is the last line above the grid that is not a footer.
    def heading_before(index)
      (index - 1).downto([ index - 4, 0 ].max) do |i|
        line = @lines[i].strip
        next if line.empty? || line.match?(FOOTER)

        return line.match?(/[a-z]{3}/) && !line.match?(/\A[A-Z][A-Za-z&,'\- ]+\([A-Z]{2,5}\)\z/) ? nil : line
      end
      nil
    end

    def parse_plan(index, heading)
      raise Invalid, "no program name above the grid" if heading.nil?

      seasons = @lines[index].scan(/(Fall|Spring|Summer) Semester/i).flatten.map(&:downcase)
      line_index = next_content(index + 1)
      starts = @lines[line_index].to_s.enum_for(:scan, COURSE_COLUMN).map { Regexp.last_match.begin(0) }
      raise Invalid, "the columns do not match the semesters" if starts.size != seasons.size || starts.empty?

      line_index = next_content(line_index + 1)
      starts = align(starts, line_index)
      state = { items: [], warnings: [], year_index: 1, rows: Array.new(starts.size) { [] }, label: nil }

      while line_index < @lines.size
        line = @lines[line_index]
        break if line.match?(HEADER) || next_plan_starts?(line_index)

        if line.strip.empty? || line.match?(FOOTER)
          line_index += 1
          next
        end
        break unless read_line(line, starts, seasons, state)

        line_index += 1
      end

      raise Invalid, "rows after the last line of totals" if state[:rows].any?(&:any?)
      raise Invalid, "grid rows after the text that ended the plan" if rows_follow?(line_index)
      raise Invalid, "no rows" if state[:items].empty?

      [ PdfCatalog::Plan.new(heading: heading, line: index + 1, items: state[:items], warnings: state[:warnings]),
        line_index ]
    end

    # Returns false at the first line after the plan: text in the left
    # margin that is not a year label.
    def read_line(line, starts, seasons, state)
      stripped = line.strip
      cells = cells_of(line)
      totals = stripped.match?(TOTALS)
      if cells.first.start < starts.first - SLACK && !(totals && stripped.start_with?("TOTAL"))
        match = cells.first.text.match(YEAR_LABEL)
        if match.nil?
          # A broken year label, such as "Sopho" with the rows beside it,
          # would cut the plan short.
          raise Invalid, "rows beside the text #{cells.first.text}" if cells.drop(1).any? { |cell| number?(cell) }

          return false
        end

        if state[:label] && state[:label].casecmp(match[1]).nonzero?
          raise Invalid, "the labels #{state[:label]} Year and #{match[1]} Year with no line of totals between them"
        end

        state[:label] = match[1]
        cells.shift
      end

      if totals
        numbers = cells.reject { |cell| cell.text.start_with?("TOTAL") }
        state[:items].concat(close_year(numbers, starts, seasons, state))
        state[:year_index] += 1
        state[:rows] = Array.new(starts.size) { [] }
        state[:label] = nil
      elsif cells.any?
        add_cells(state[:rows], cells, starts)
      end
      true
    end

    # Text in the margin ends a plan. When grid rows come right after it,
    # the text was a part of the plan that the parser cannot read.
    def rows_follow?(index)
      return false if index >= @lines.size || @lines[index].match?(HEADER) || next_plan_starts?(index)

      following = index
      3.times.any? do
        following = next_content(following + 1)
        following < @lines.size && row_like?(@lines[following])
      end
    end

    def row_like?(line)
      cells_of(line).each_cons(2).any? { |cell, credits| cell.text.match?(PdfRowReader::ONE_CODE) && number?(credits) }
    end

    def next_content(index)
      index += 1 while index < @lines.size && (@lines[index].strip.empty? || @lines[index].match?(FOOTER))
      index
    end

    # The next plan's name, with its grid right under it.
    def next_plan_starts?(index)
      return false if @lines[index].strip.empty?

      following = next_content(index + 1)
      following < @lines.size && @lines[following].match?(HEADER)
    end

    # The rows of a grid can start a few characters away from the "Course"
    # header, when a page break falls between them. The first row moves the
    # columns.
    def align(starts, index)
      first = index < @lines.size && cells_of(@lines[index]).first
      return starts unless first

      shift = first.start - starts.first
      shift.abs > SLACK ? starts.map { |start| start + shift } : starts
    end

    # Splits a line where two or more spaces are, and keeps where each part starts.
    # The 2015-2016 export sometimes leaves one space between the credits and
    # the next column: "6 ARCH1500" is two cells.
    def cells_of(line)
      line.enum_for(:scan, /\S+(?: \S+)*/).flat_map do
        text = Regexp.last_match[0]
        start = Regexp.last_match.begin(0)
        if (split = text.match(/\A(\d{1,2}) ([A-Z]{2,}\S*.*)\z/))
          [ Cell.new(text: split[1], start: start), Cell.new(text: split[2], start: start + split.begin(2)) ]
        else
          [ Cell.new(text: text, start: start) ]
        end
      end
    end

    def column_of(cell, starts)
      starts.rindex { |start| start <= cell.start + SLACK } || 0
    end

    # A number on a line is the credits of the text cell before it, so it
    # belongs to that cell's column. The credits sit at the right edge of a
    # column, close to the next one.
    def add_cells(rows, cells, starts)
      cells.each_with_index do |cell, position|
        if number?(cell)
          raise Invalid, "credits with no code: #{cell.text}" if position.zero? || number?(cells[position - 1])

          next
        end

        column = column_of(cell, starts)
        following = cells[position + 1]
        if following && number?(following)
          rows[column] << Row.new(cell.text, following.text.to_i, [])
        elsif rows[column].empty?
          raise Invalid, "text with no row above it: #{cell.text}"
        else
          rows[column].last.title_lines << cell.text
        end
      end
    end

    def number?(cell) = cell.text.match?(/\A\d{1,2}\z/)

    # A total that does not match its rows is a warning, not a reason to
    # leave the plan out: the catalogs have such typos (16 credits of rows
    # under a total of 20). The review queue shows the warnings.
    def close_year(totals, starts, seasons, state)
      year_index = state[:year_index]
      label = state[:label]
      if label && PdfCatalog::YEAR_WORDS[label.downcase] != year_index
        raise Invalid, "year #{year_index} has the label #{label} Year"
      end

      # A line with a total for every column gives them in order. It can be
      # on the next page, where the columns sit in other places. A shorter
      # line places each total by where it is: at the right edge of its
      # column, so it needs no slack.
      by_column = if totals.size == starts.size
                    totals.each_with_index.to_h { |cell, column| [ column, [ cell ] ] }
      else
                    totals.group_by { |cell| starts.rindex { |start| start <= cell.start } || 0 }
      end
      raise Invalid, "two totals in one column of year #{year_index}" if by_column.values.any? { |cells| cells.size > 1 }

      state[:rows].each_with_index.flat_map do |column_rows, column|
        total = by_column[column]&.first&.text&.to_i
        sum = column_rows.sum(&:credits)
        if (total || 0) != sum
          state[:warnings] << "Year #{year_index} #{seasons[column]}: the rows add up to #{sum} credits, " \
                              "the printed total is #{total || 'missing'}."
        end

        column_rows.map { |row| item(row, year_index, seasons[column]) }
      end
    end

    def item(row, year_index, season)
      attributes = PdfRowReader.read(row.cell, row.title_lines.join(" "))
      raise Invalid, "cannot read the row #{row.cell}" if attributes.nil?

      PdfCatalog::Item.new(year_index: year_index, season: season, min_credits: row.credits, max_credits: row.credits,
                           **attributes)
    end
  end
end
