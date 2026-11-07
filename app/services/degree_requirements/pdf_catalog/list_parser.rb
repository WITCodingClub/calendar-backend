# frozen_string_literal: true

module DegreeRequirements
  module PdfCatalog
    # Reads the plans of study of the 2016-2017 to 2018-2019 catalogs from
    # `pdftotext -layout` text. Each semester is a heading with one course a
    # line under it:
    #
    #   Applied Mathematics (BSAM)
    #   All courses are four (4) credits unless otherwise noted
    #   First Year, Fall Semester (total credits 20)
    #   MATH1550, Foundations of Applied Mathematics
    #   COMP1000                Computer Science I 4cr.
    #   HSS ELECTIVE, See ENGL/HSS note below *
    #   or
    #   COOP3000                Pre-Cooperative Work Term (0 credits)
    #
    # The program name with its code in parentheses comes before the first
    # heading. A line that is not a course ends the semester, so the
    # elective lists after a plan are not read as part of it.
    class ListParser
      HEADING = /\A\s*(Freshman|Sophomore|Junior|Senior|First|Second|Third|Fourth|Fifth)\s+Year,?\s+(Fall|Spring|Summer)\s+Semester\b(?:\s*\((?:total credits\s*)?(\d+))?/i
      YEARS = { "freshman" => 1, "first" => 1, "sophomore" => 2, "second" => 2, "junior" => 3, "third" => 3,
                "senior" => 4, "fourth" => 4, "fifth" => 5 }.freeze
      SEASON_ORDER = %w[fall spring summer].freeze
      TITLE = /\A\s*(?:Curriculum for\s+)?([A-Z][\w&,.'’\/ -]+?)\s*\(([A-Z]{2,6})\)\s*\z|\A\s*([A-Z][\w&,.'’\/ –-]+ Concentration)\s*\z/
      # "CODE, Title", "CODE<tab or spaces>Title", or the code alone.
      ITEM = /\A\s*(?:[•·▪]\s*)?(?<code>[A-Z]{2,5} ?\d{3,4}[A-Z]?|(?:[A-Z][A-Z&\/-]* ){0,3}(?:ELECTIVES?|ENGLISH|SCIENCE))\*?(?:,\s*|\s{2,}|\t+\s*|\s+|\z)(?<title>.*)\z/
      CREDITS = /\((\d{1,2}(?:-\d{1,2})?)\s*credits?\)|\b(\d{1,2}(?:-\d{1,2})?)\s*cr\.?(?=\s|\z)/i
      DEFAULT_FOUR = /all courses are four \(4\) credits/i
      FOOTER = /\A\s*\d{1,3}\s*\z/
      # How far before the first heading the program name can be.
      TITLE_LINES = 20
      # How far back to look for the name of a program with no name near
      # its first heading: its description can run for a few pages.
      FAR_TITLE_LINES = 200

      def self.call(text) = new(text).call

      def initialize(text)
        @lines = text.to_s.split("\n")
      end

      def call
        programs = []
        current = nil
        last_key = nil
        index = 0

        while index < @lines.size
          match = HEADING.match(clean(index))
          unless match
            index += 1
            next
          end

          key = [ YEARS.fetch(match[1].downcase), SEASON_ORDER.index(match[2].downcase) ]
          title_index = title_before(index, current && current[:heading_index])
          # A plan starts again at the first fall. Another step back is a typo
          # in the catalog, such as two "Sophomore Year, Fall Semester".
          restart = current.nil? || title_index || (key == [ 1, 0 ] && last_key && last_key != key)
          title_index ||= title_before(index, current && current[:heading_index], FAR_TITLE_LINES) if restart
          if restart
            programs << finish(current) if current
            current = start(title_index, index)
          end
          last_key = key
          current[:heading_index] = index

          items, index = read_semester(index + 1, key[0], SEASON_ORDER[key[1]], current[:default_credits])
          items = fill_credits(items, match[3]&.to_i)
          current[:items].concat(items)
        end
        programs << finish(current) if current
        programs.compact
      end

      private

      def start(title_index, heading_index)
        title = title_index && TITLE.match(clean(title_index))
        prelude = ((title_index || heading_index)...heading_index).map { |i| clean(i) }.join(" ")
        name = title && (title[3] ? title[3].squeeze(" ") : "#{title[1].strip} (#{title[2]})")
        { title: name, code: title && title[2], page: page_of(heading_index),
          default_credits: prelude.match?(DEFAULT_FOUR) ? 4 : nil, items: [] }
      end

      def finish(program)
        return nil if program[:items].empty? || program[:title].nil?

        items = program[:items]
        plan = ProgramPageParser::Plan.new(name: program[:title], years: items.map(&:year_index).max,
                                           accelerated: program[:title].match?(/three[\s-]year|accelerated/i),
                                           total_credits: ItemBuilder.total_credits(items), items: items)
        Program.new(title: program[:title], code: program[:code], page: program[:page], plan: plan)
      end

      # The rows under one heading, and the index of the line after them.
      def read_semester(index, year, season, default_credits)
        cells = []
        join_next = false
        while index < @lines.size
          line = clean(index)
          break if line.match?(HEADING)

          index += 1
          next if line.strip.empty? || line.match?(FOOTER)

          if line.strip.match?(/\Aor\z/i)
            join_next = cells.any?
            next
          end

          match = ITEM.match(line)
          if match.nil?
            # A title that runs onto a second, deeper line: "(1 credit)".
            break unless cells.any? && line[/\A */].size > cells.last[:x] + 4

            cells.last[:title] = "#{cells.last[:title]} #{line.strip}"
            next
          end

          cell = cell_for(match, default_credits)
          if join_next && ItemBuilder::COURSE.match?(cell[:code]) && ItemBuilder::COURSE.match?(cells.last[:code].split(" or ").last)
            cells.last[:code] = "#{cells.last[:code]} or #{cell[:code]}"
          else
            cells << cell
          end
          join_next = false
        end

        items = cells.flat_map do |cell|
          code, title, credits = finish_cell(cell, default_credits)
          ItemBuilder.build(code, title, credits, year_index: year, season: season)
        end
        [ items, index ]
      end

      # Most lines in 2016-2017 and 2017-2018 print no credits. When the
      # semester total is four credits for each course with none, each of
      # them has four, the usual size of a course.
      def fill_credits(items, total)
        blank = items.select { |item| item.min_credits.nil? && item.kind != "choice" || item.kind == "choice" && item.min_credits.nil? }
        return items if total.nil? || blank.empty?

        known = items.sum { |item| item.min_credits.to_i }
        return items unless total - known == 4 * blank.size

        items.map { |item| item.min_credits.nil? ? item.with(min_credits: 4, max_credits: 4) : item }
      end

      def cell_for(match, _default_credits)
        { code: match[:code].squeeze(" "), title: match[:title].to_s.strip, x: match.begin(:code) }
      end

      # [code, title, credits] of a cell. "ENGR1600 Fundamentals of CAD &
      # CAM (1 credit) or ENGR1800 Introduction to MATLAB" is a choice.
      def finish_cell(cell, default_credits)
        code = cell[:code]
        title = cell[:title]
        if (other = title.match(/\s+or\s+([A-Z]{2,5} ?\d{3,4})\b/))
          code = "#{code} or #{other[1]}"
          title = title[0...other.begin(0)]
        end
        credits = title[CREDITS, 1] || title[CREDITS, 2]
        title = title.gsub(CREDITS, "").strip.delete_suffix(",").strip
        credits ||= code.start_with?("COOP") ? 0 : default_credits
        [ code, title, credits ]
      end

      # The line with the program name, between the last heading and this
      # one, or nil.
      def title_before(index, previous_heading, lines = TITLE_LINES)
        floor = [ index - lines, (previous_heading || -1) + 1, 0 ].max
        (index - 1).downto(floor).find { |i| clean(i).match?(TITLE) }
      end

      def page_of(index)
        @page_starts ||= @lines.each_index.select { |i| @lines[i].include?("\f") }
        1 + @page_starts.count { |start| start <= index }
      end

      def clean(index) = @lines[index].to_s.delete("\f")
    end
  end
end
