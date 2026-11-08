# frozen_string_literal: true

module DegreeRequirements
  module PdfCatalog
    # Reads the plans of study of the 2013-2014 to 2015-2016 catalogs from
    # `pdftotext -layout` text. Each plan is a Word table with a column for
    # each semester:
    #
    #                          COMPUTER NETWORKING (BSCN)
    #           Fall Semester              Spring Semester         Summer Semester
    #           Course            Credits  Course         Credits  Course    Credits
    #           COMP105                4   COMP201             4
    #           Intro to Networking and    Computer Science II
    #   Freshman Systems
    #                                 16                      16
    #
    # A cell starts with a code and its credits, and the lines under it are
    # the title. A line with only numbers is the total of one year, so it
    # ends the year. The year names in the left margin are skipped: Word
    # centers them, and splits "Sopho-more" over lines.
    class GridParser
      HEADER = /Fall Semester\s+Spring Semester/
      SEMESTER = /(Fall|Spring|Summer) Semester/
      FOOTER = /Academic Catalog\s+\d+/
      PAGE_NUMBER = /\A\s*\d{1,3}\s*\z/
      # Word sometimes breaks the year name over lines: "S", "o", "p", or
      # "Fres", "hma", "n".
      YEAR_LABEL = /\A(?:(?i:(?:Freshman|Sophomore|Sopho|more|Junior|Senior|Middler|First|Second|Third|Fourth|Fifth)(?: Year)?|Year)|[A-Z]?[a-z]{1,3}|[A-Z])\z/
      # "4", "3-4", "3/4", or "(6)" for an optional course.
      NUMBER = %r{\A\(?\d{1,3}(?:[-/]\d{1,2})?\)?\z}
      TOTAL = /\ATOTAL( CREDITS)?\z/i
      # A title or code this far left of a column start is still in it.
      SLACK = 3
      # Running text that starts left of this x and is this long is not a
      # cell: a table cell is narrower.
      MARGIN = 8
      PROSE_LENGTH = 45
      # The furthest a table moves over a page break.
      MAX_SHIFT = 14
      # Codes this far apart are in different columns.
      COLUMN_GAP = 12
      # The longest table, with its page breaks, is about 90 lines.
      SURVEY_LINES = 140
      # "TMGT8000 Strategic" or "ELECTIVE CONM 3800": a code with more text.
      CODE_AND_TITLE = /\A(?:ELECTIVE )?([A-Z]{2,7} ?\d{3,4}[A-Z]?)(?: ([A-Z][a-z].*))?\z/
      # A subject with no number ("CIVE" over "Civil Engineering Capstone
      # Design") is a course slot of that subject when credits follow it.
      SUBJECT_ONLY = /\A[A-Z]{4}\z/

      def self.call(text) = new(text).call

      def initialize(text)
        @lines = text.to_s.split("\n")
      end

      def call
        programs = []
        index = 0
        while index < @lines.size
          if @lines[index].match?(HEADER)
            program, index = parse_table(index)
            programs << program if program
          else
            index += 1
          end
        end
        programs
      end

      private

      # Returns [Program or nil, the index of the next line to read].
      def parse_table(header_index)
        header = clean(@lines[header_index])
        seasons = header.scan(SEMESTER).flatten.map(&:downcase)
        columns, labelled_totals = survey(header_index + 1)
        return [ nil, header_index + 1 ] if columns.empty?

        title = title_before(header_index)
        cells = Array.new(columns.size)
        rows = Hash.new { |hash, key| hash[key] = [] }
        year = 1
        # The total rows. Their numbers are not used: some print a grand total
        # in a semester column.
        totals = []
        # The column starts before the last page break, and the columns
        # with a code on this page so far.
        page_base = nil
        placed = []
        index = header_index + 1

        while index < @lines.size
          line = clean(@lines[index])
          index += 1
          next if line.strip.empty? || line.match?(/\bCourse\b.*\bCourse\b/)

          if footer?(index - 1)
            page_base = columns
            placed = []
            next
          end

          tokens = tokens_of(line)
          if page_base && placed.size < columns.size
            columns, placed = realign(page_base, columns, placed, code_xs(tokens))
          end
          # A page break can move the "TOTAL CREDITS" row into the margin.
          margin, body = tokens.partition { |text, x| outside?(text, x, columns.first) }
          if margin.any? { |text, _| !text.match?(YEAR_LABEL) } || line.match?(HEADER) || prose?(line)
            index -= 1
            break
          end
          next if body.empty?

          if total_line?(body, labelled_totals)
            flush_all(cells, rows, year, seasons)
            totals << line
            year += 1
            next
          end

          # The columns whose start on this page is still a guess.
          guessed = page_base ? columns.each_index.to_a - placed : []
          body.each { |text, x| add_token(cells, rows, columns, text, x, year, seasons, guessed) }
        end
        flush_all(cells, rows, year, seasons)

        items = rows.keys.sort.flat_map { |key| rows[key] }
        # Each year ends with a total row, but the last year of a graduate
        # plan can have none. Rows after the last total with no course in
        # them are text under the table, such as a "FACULTY" heading.
        trailing = items.select { |item| item.year_index > totals.size }
        items -= trailing if totals.any? && trailing.none? { |item| item.kind != "placeholder" }
        return [ nil, index ] if items.empty?

        plan = ProgramPageParser::Plan.new(name: plan_name(title), years: items.map(&:year_index).max,
                                           accelerated: title.to_s.match?(/three[\s-]year|accelerated/i),
                                           total_credits: ItemBuilder.total_credits(items), items: items)
        [ Program.new(title: title, code: title.to_s[/\(([A-Z]{2,6})\)\s*\z/, 1], page: page_of(header_index), plan: plan), index ]
      end

      # A code starts a cell, "OR" joins the next code to it, a number is
      # its credits, and other text is its title. A number goes to the
      # column it is in without slack: the credits are right-aligned close
      # to the code of the next column.
      def add_token(cells, rows, columns, text, x, year, seasons, guessed = [])
        number = text.match?(NUMBER)
        column = columns.rindex { |start| start - (number ? 0 : SLACK) <= x } || 0
        # After a page break a column start is a guess until a code is
        # under it. Credits with no open cell to take them are for the
        # column on the left.
        if number && guessed.include?(column) && column.positive? && !open_cell?(cells[column]) && open_cell?(cells[column - 1])
          column -= 1
        end
        cell = cells[column]

        if ItemBuilder.code?(text)
          if cell&.dig(:or)
            cell[:code] = "#{cell[:code]} or #{ItemBuilder.clean_code(text)}"
            cell[:title] << "or" if cell[:title].any?
            cell[:or] = false
          else
            flush(cells, column, rows, year, seasons)
            cells[column] = { code: text, title: [], credits: nil }
          end
        elsif cell.nil?
          nil
        elsif text.match?(/\AOR\z/i)
          cell[:or] = true
        elsif !cell[:or] && text.match?(/\s+OR\z/)
          # "Mechanical Graphics OR" over the next code.
          cell[:title] << text.sub(/\s+OR\z/, "")
          cell[:or] = true
        elsif number
          # The second number of a choice repeats the credits.
          cell[:credits] ||= text
        elsif cell[:or]
          # "Concentration Course II OR" over "Advanced Practicum": the other
          # choice has no code, so the cell is one slot with both names.
          cell[:title] << "or" << text
          cell[:or] = false
        else
          cell[:title] << text
        end
      end

      # The tokens of a line with "CIVE" followed by its credits changed to
      # the slot code "CIVEXXX".
      def subject_slots(body)
        body.each_with_index.map do |(text, x), i|
          following = body[i + 1]
          slot = text.match?(SUBJECT_ONLY) && following && following[0].match?(NUMBER) && !ItemBuilder.code?(text)
          slot ? [ "#{text}XXX", x ] : [ text, x ]
        end
      end

      def open_cell?(cell) = cell && cell[:credits].nil?

      # Reads ahead to the end of the table. Returns the x where each column
      # starts (the leftmost code of each cluster of codes), and whether the
      # table prints "TOTAL CREDITS" on its total rows. Some tables put the
      # credits on a line of their own, so a line of numbers is a total only
      # when the table has no such label.
      def survey(start)
        # The x of each code, one list for each page.
        pages = [ [] ]
        labelled = false
        (start...[ start + SURVEY_LINES, @lines.size ].min).each do |i|
          line = clean(@lines[i])
          next if line.strip.empty?

          if footer?(i)
            pages << [] if pages.last.any?
            next
          end
          break if line.match?(HEADER) || prose?(line)

          tokens = tokens_of(line)
          # Text left of every code so far, other than a year name, is past the end.
          left = pages.flatten.min
          break if left && tokens.any? { |text, x| outside?(text, x, left) && !text.match?(YEAR_LABEL) }

          labelled ||= line.match?(/TOTAL CREDITS/)
          pages.last.concat(code_xs(tokens))
        end

        columns = pages.reject(&:empty?).reduce([]) { |base, xs| add_page(base, columns_of(xs)) }
        [ columns.first(3), labelled ]
      end

      def columns_of(xs)
        xs.sort.each_with_object([]) { |x, columns| columns << x if columns.empty? || x - columns.last > COLUMN_GAP }
      end

      def code_xs(tokens) = tokens.filter_map { |text, x| x if ItemBuilder.code?(text) }

      # The columns of the first page, with any column that only a later
      # page has (often the summer column) moved back to first-page x.
      def add_page(base, page_columns)
        return page_columns if base.empty?

        matched = align(base, page_columns)
        return base if matched.empty?

        back = matched.map { |i, x| [ x, base[i] ] }
        extra = (page_columns - matched.values).map { |x| map_x(back, x) }
        columns_of(base + extra)
      end

      # Word can print the rest of a table a few characters further left or
      # right on the next page, and can stretch it, so each column can move
      # by a different amount. Each code on the first lines of the new page
      # places the column it is in. Returns the columns and the indexes of
      # the columns placed so far.
      def realign(page_base, columns, placed, xs)
        return [ columns, placed ] if xs.empty?

        matched = align(page_base, xs)
        placed |= matched.keys
        moved = placed.to_h { |i| [ i, matched[i] || columns[i] ] }
        pairs = moved.map { |i, x| [ page_base[i], x ] }
        [ page_base.each_index.map { |i| moved[i] || map_x(pairs, page_base[i]) }, placed ]
      end

      # { column index => x } for each column with an x up to MAX_SHIFT from
      # its start.
      def align(columns, xs)
        columns.each_with_index.each_with_object({}) do |(start, i), found|
          x = xs.select { |candidate| (candidate - start).abs <= MAX_SHIFT }.min_by { |candidate| (candidate - start).abs }
          found[i] = x if x
        end
      end

      # Moves x from one page to the other with [[x on one page, x on the
      # other], ...] of the columns placed on both: one pair gives a shift,
      # two give a shift and a scale.
      def map_x(pairs, x)
        return x if pairs.empty?

        (from_a, to_a), (from_b, to_b) = pairs.sort.values_at(0, -1)
        return x + to_a - from_a if from_a == from_b

        (to_a + ((to_b - to_a).to_f / (from_b - from_a) * (x - from_a))).round
      end

      # Is a token left of the table? A page break can move the next page
      # a few characters left, and the "TOTAL CREDITS" row into the margin.
      def outside?(text, x, left)
        return false if text.match?(TOTAL)

        x < left - SLACK || (x < left && text.length > PROSE_LENGTH)
      end

      # A line of running text at the left edge ends a table.
      def prose?(line)
        first = tokens_of(line).first
        first && first[1] < MARGIN && first[0].length > PROSE_LENGTH
      end

      def total_line?(body, labelled)
        return false if labelled && body.none? { |text, _| text.match?(TOTAL) }

        numbers = body.count { |text, _| text.match?(NUMBER) }
        numbers.positive? && body.all? { |text, _| text.match?(NUMBER) || text.match?(TOTAL) }
      end

      # rows is keyed by [year, season order], so the items sort by semester.
      def flush(cells, column, rows, year, seasons)
        cell = cells[column]
        return if cell.nil?

        cells[column] = nil
        season = seasons[column] || "fall"
        key = [ year, %w[fall spring summer].index(season) || column ]
        code, title = ItemBuilder.split_choice(cell[:code], cell[:title].join(" "))
        rows[key].concat(ItemBuilder.build(code, title, cell[:credits], year_index: year, season: season))
      end

      def flush_all(cells, rows, year, seasons)
        cells.each_index { |column| flush(cells, column, rows, year, seasons) }
      end

      # The heading over the table: the last line above it that is not empty
      # and not a page footer.
      def title_before(header_index)
        (header_index - 1).downto([ header_index - 6, 0 ].max) do |i|
          line = clean(@lines[i]).strip
          next if line.empty? || footer?(i)

          # "(BSAM[MM10])": a Word comment mark.
          return line.gsub(/\[[A-Z]{1,4}\d*\]/, "").gsub(/\s+/, " ")
        end
        nil
      end

      # "COMPUTER NETWORKING (BSCN)" names the plan "Computer Networking (BSCN)".
      def plan_name(title)
        return "Plan of Study" if title.blank?

        title.split(/(\s+|\(|\)|-|–)/).map { |part| part.match?(/\A[A-Z]{2,6}\z/) && title.include?("(#{part})") ? part : part.capitalize }
             .join.then { |name| name.gsub(/\b(And|Of|In|The|For)\b/) { ::Regexp.last_match(1).downcase } }
      end

      # [[text, x], ...]: runs of text with less than two spaces in them. A
      # narrow column can leave one space between the credits and the next
      # code ("6 ARCH1500"), so a number at the start of a run is split off.
      # A code with its title on the same line ("TMGT8000 Strategic") and
      # "ELECTIVE CONM 3800" are split into a code and a title, and "CIVE"
      # before its credits is the slot "CIVEXXX".
      def tokens_of(line)
        subject_slots(raw_tokens(line))
      end

      def raw_tokens(line)
        line.enum_for(:scan, /\S+(?: \S+)*/).flat_map do
          text = Regexp.last_match(0)
          x = Regexp.last_match.begin(0)
          if (split = text.match(/\A(\d{1,2}) (\S.*)\z/)) && ItemBuilder.code?(split[2])
            [ [ split[1], x ], [ split[2], x + split.begin(2) ] ]
          elsif (split = text.match(CODE_AND_TITLE)) && ItemBuilder.code?(split[1])
            [ [ split[1], x + split.begin(1) ], ([ split[2], x + split.begin(2) ] if split[2]) ].compact
          else
            [ [ text, x ] ]
          end
        end
      end

      def page_of(index)
        @page_starts ||= @lines.each_index.select { |i| @lines[i].include?("\f") }
        1 + @page_starts.count { |start| start <= index }
      end

      # A page footer: "2015-2016 Academic Catalog 124", or a page number
      # just before a page break. A number alone on a line in a table is
      # the credits of a cell.
      def footer?(index)
        line = clean(@lines[index])
        line.match?(FOOTER) || (line.match?(PAGE_NUMBER) && @lines[index..(index + 3)].any? { |raw| raw.to_s.include?("\f") })
      end

      # "¾" is a range of 3 to 4 credits.
      def clean(line) = line.to_s.delete("\f").gsub("¾", "3/4").tr("⁄", "/")
    end
  end
end
