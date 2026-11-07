# frozen_string_literal: true

module DegreeRequirements
  module PdfCatalog
    # Reads the plans of study of the 2025-2026 CourseLeaf PDF. Its pages
    # have two columns, so Text extracts each half of a page on its own and
    # puts the left half first. A plan reads:
    #
    #   Four Year Program
    #   First Year
    #   Fall Semester                                   Credits
    #   COMP1000         COMPUTER SCIENCE I                 4
    #   COMP1100 or COMP2100 ...                            4
    #   HSS Elective*                                       4
    #                    Credits                           16
    #   ...
    #                    Total Credits                    128
    #
    # The plan name is only "Four Year Program", so the program comes from
    # the table of contents ("Computer Science, B.S. (p. 104)") and the page
    # number printed at the foot of each page.
    class CourseLeafParser
      YEAR = /\A\s*(First|Second|Third|Fourth|Fifth) Year\s*\z/
      YEARS = %w[first second third fourth fifth].freeze
      SEASON = /\A\s*(Fall|Spring|Summer) Semester\b/
      # "Computer Science Bachelor of Science ........ 104" in the table of
      # contents at the front.
      TOC = /\A\s*(?<name>[A-Z][^.]*?[a-z)])\s*\.{4,}\s*(?<page>\d{1,3})\s*\z/
      CODE = /[A-Z]{2,5}\d{4}/
      NUMBER = /\A\d{1,2}(?:-\d{1,2})?\z/
      PAGE_NUMBER = /\A\s*(\d{1,3})\s*\z/
      FOOTER = /\A\s*\d{4}-\d{4} Academic Catalog\s*\z/
      SMALL_WORDS = %w[and as at by for in of on or the to with].freeze
      NAME_LINES = 8
      # "Four Year Program", "Master of Architecture (2-Year Track)",
      # "Construction Management (Dual Degree)". A line of a paragraph ends
      # with a full stop.
      PLAN_NAME = /\A[A-Z][^.•]*\b(?:Program|Track|Degree\)|Plan|Option)\s*\z/
      CONTENTS_PAGES = 12
      PROGRAM_NAME = /Bachelor|Master|Minor|Certificate|Concentration|Track|Degree/

      def self.call(text) = new(text).call

      def initialize(text)
        @pages = text.to_s.split("\f").map { |page| page.split("\n") }
      end

      def call
        programs = []
        plan = nil
        @pages.each_with_index do |lines, page_index|
          lines.each_with_index do |line, line_index|
            if (match = YEAR.match(line))
              # A plan with no "Total Credits" line ends at the next plan.
              if plan && plan[:rows].any? && match[1] == "First"
                programs << finish(plan)
                plan = nil
              end
              plan ||= start_plan(page_index, line_index)
              plan[:year] = YEARS.index(match[1].downcase) + 1
            elsif plan.nil?
              next
            elsif (match = SEASON.match(line))
              plan[:season] = match[1].downcase
            elsif line.strip.start_with?("Total Credits")
              programs << finish(plan)
              plan = nil
            else
              read_row(plan, line)
            end
          end
        end
        programs << finish(plan) if plan
        programs.compact
      end

      private

      def start_plan(page_index, line_index)
        { name: plan_name(page_index, line_index), page: page_index + 1, year: 1, season: "fall", rows: [] }
      end

      # One line of a semester: a course, a choice, a placeholder, the
      # semester total, or the rest of a title.
      def read_row(plan, line)
        tokens = line.strip.split(/\s{2,}/)
        return if tokens.empty? || tokens.first == "Credits" || line.match?(PAGE_NUMBER) || line.match?(FOOTER)

        credits = tokens.last.match?(NUMBER) ? tokens.pop : nil
        first = tokens.first.to_s
        row = { year: plan[:year], season: plan[:season], credits: credits }

        if first.match?(/\Aor\s+#{CODE}/) && (last = plan[:rows].last)
          last[:codes].concat(first.scan(CODE))
          last[:choice] = true
        elsif first.match?(/\A#{CODE}/)
          codes = first.scan(CODE)
          plan[:rows] << row.merge(codes: codes, choice: first.match?(/\bor\b/), title: tokens[1..].join(" "))
        elsif line.match?(/\A\S/) && credits
          plan[:rows] << row.merge(codes: [], label: first)
        elsif (last = plan[:rows].last) && last[:codes].any? && credits.nil?
          last[:title] = [ last[:title], tokens.join(" ") ].compact_blank.join(" ")
        end
      end

      def finish(plan)
        items = plan[:rows].flat_map { |row| items_for(row) }
        return nil if items.empty?

        name = plan[:name] || "Plan of Study"
        Program.new(title: program_name(plan[:page]), code: nil, page: plan[:page],
                    plan: ProgramPageParser::Plan.new(name: name, years: items.map(&:year_index).max,
                                                      accelerated: name.match?(/three[\s-]year|3[\s-]year|accelerated/i),
                                                      total_credits: ItemBuilder.total_credits(items), items: items))
      end

      def items_for(row)
        if row[:codes].empty?
          label = row[:label].delete_suffix("*").strip
          footnote = "*" if row[:label].end_with?("*")
          return ItemBuilder.build("ELECTIVE", label, row[:credits], year_index: row[:year], season: row[:season])
                            .map { |item| item.with(label: label, footnote: footnote) }
        end

        code = row[:codes].join(row[:choice] ? " or " : " & ")
        ItemBuilder.build(code, title_case(row[:title]), row[:credits], year_index: row[:year], season: row[:season])
      end

      # "COMPUTER SCIENCE II" reads "Computer Science II".
      def title_case(text)
        text.to_s.downcase.split.each_with_index.map do |word, index|
          if word.match?(/\A[ivx]+\z/) && index.positive? then word.upcase
          elsif SMALL_WORDS.include?(word) && index.positive? then word
          else word.capitalize
          end
        end.join(" ")
      end

      # The last line above the first year that names the plan, such as
      # "Four Year Program" or "Master of Architecture (2-Year Track)".
      def plan_name(page_index, line_index)
        lines = @pages[page_index][0...line_index].reverse.first(NAME_LINES)
        lines += (@pages[page_index - 1] || []).reverse.first(NAME_LINES) if page_index.positive?
        lines.map(&:strip).find { |line| line.match?(PLAN_NAME) && line.length <= 70 }
      end

      # The program whose page in the table of contents is the last one at
      # or before the printed page of the plan.
      def program_name(pdf_page)
        printed = printed_page(pdf_page)
        return nil if printed.nil?

        # A department and its first program start on the same page. The
        # program is listed after the department.
        name = contents.select { |_, start| start <= printed }.max_by.with_index { |(_, start), i| [ start, i ] }&.first
        # A plan under a department heading ("Engineering") is of one of its
        # programs, and the contents do not say which.
        name if name.to_s.match?(PROGRAM_NAME)
      end

      def contents
        @contents ||= @pages.first(CONTENTS_PAGES).flatten.filter_map do |line|
          match = TOC.match(line)
          match && [ match[:name].squeeze(" "), match[:page].to_i ]
        end
      end

      # The number printed at the foot of a page, from the offset of the
      # pages that print one.
      def printed_page(pdf_page)
        @offsets ||= @pages.each_with_index.filter_map do |lines, index|
          number = lines.reverse.first(6).find { |line| line.match?(PAGE_NUMBER) }
          number && (index + 1) - number.to_i
        end
        offset = @offsets.tally.max_by(&:last)&.first
        offset && pdf_page - offset
      end
    end
  end
end
