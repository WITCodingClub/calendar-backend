# frozen_string_literal: true

module DegreeRequirements
  # Reads the plans of study of the 2016-2017 to 2018-2019 catalogs. Each
  # plan is a list under a heading for each semester:
  #
  #   Computer Science (BCOS)
  #   Freshman Year, Fall Semester (total credits 16)
  #   • COMP1000, Computer Science I
  #   • ENGLISH, English Sequence, See ENGL/HSS note below *
  #   Freshman Year, Spring Semester (total credits 16)
  #   ...
  #
  # 2018-2019 puts the credits after each title: "ARCH1000   Studio 01 (6 credits)".
  #
  # A plan starts at a first-year heading, and its semesters must follow in
  # order. Text that is not a row ends the rows of a semester. A program name
  # between two semesters of one plan, such as a concentration in the middle
  # of a plan, leaves the plan out: the parser cannot tell which rows belong
  # to which program.
  class PdfListParser
    SEMESTER = /\A(?:•\s*)?(Freshman|First|Sophomore|Second|Junior|Third|Senior|Fourth|Fifth)\s+Year,?\s+
                (Fall|Spring|Summer)(?:\s+Semester)?\s*(?:\((?:total\s+)?credits:?\s*(\d+(?:-\d+)?)\))?\s*:?\z/ix
    BULLET = /\A•\s*/
    TWO_ROWS = /(?<=\d\scr\.|\dcr\.|\scredits\)|\scredit\))\s+(?=[A-Z]{2,5}\s?\d{3,4}\b|[A-Z]{2,}\s?,|ELECTIVE|ENGLISH)/
    ONLY_CREDITS =/\A\(?(\d{1,2})\s*credits?\)?\z/i
    COURSE = /\A([A-Z]{2,5}) ?(\d{3,4})\b\s*[,.:]?\s*(.*)\z/
    # A slot in capitals and its text: "HSS ELECTIVE, See ENGL/HSS note
    # below", "EC   Engineering Concentration (4 credits)". A line in
    # capitals alone is a placeholder only with ELECTIVE or ENGLISH in it,
    # so a heading such as "DEGREE DETAILS" is not a row.
    PLACEHOLDER = /\A([A-Z][A-Z\/&-]+(?:\s(?:or\s)?[A-Z][A-Z\/&-]+)*)(?:\s*,\s*|\s+)(\S.*[^:])\z/
    SLOT = /\A(?:[A-Z\/&-]+\s)*(?:ELECTIVE|ENGLISH)S?\z/
    # A program name on a line of its own: "Computer Science (BCOS)",
    # "Curriculum for Computer Science (BCOS)", "Construction Management
    # (BSCM) with concentration in Facilities Management", "Architecture -
    # Urbanism Concentration", or "Master of Architecture (One-Year)".
    NAME = /[A-Z][A-Za-z&'\- ]+/
    HEADING = /\A(?:
      (?:Curriculum\sfor\s)?#{NAME.source}\s\([A-Z]{2,5}\)(?:\sCurriculum|\swith\sconcentration(?:\sin\s#{NAME.source})?)?
      |#{NAME.source}\s-\s#{NAME.source}\sConcentration
      |Master\sof\s#{NAME.source}(?:\s\([A-Za-z\-]+\))+
    )\z/x
    HEADING_LIMIT = 90
    # After this many lines of text, a plan has ended.
    PROSE_LIMIT = 25

    class Invalid < StandardError; end

    def self.call(text) = new(text).call

    def initialize(text)
      @lines = text.to_s.lines(chomp: true).map { |line| line.tr("\t", " ") }
    end

    def call
      @plans = []
      @rejections = []
      @plan = nil
      @last_end = -1
      @fragment_reported = false
      index = 0
      while index < @lines.size
        index = read_line(index)
      end
      close_plan
      PdfCatalog::Result.new(plans: @plans, rejections: @rejections)
    end

    private

    # Returns the index of the next line to read.
    def read_line(index)
      stripped = squish(@lines[index])
      return index + 1 if stripped.empty? || stripped.match?(PdfCatalog::FOOTER)

      if (match = stripped.match(SEMESTER))
        start_semester(index, match)
        return index + 1
      end
      return index + 1 if @plan.nil?

      if @plan[:accepting] && item_line?(stripped)
        text = stripped.sub(BULLET, "")
        # "ENGR1600, Fundamentals of CAD & CAM OR" goes on in the next line.
        if text.match?(/\bOR\z/i) && (following = next_content(index + 1))
          text = "#{text} #{squish(@lines[following]).sub(BULLET, '')}"
          index = following
        end
        # "ELECTIVE, Biomedical Engineering 4cr. ELECTIVE, Engineering 4cr."
        # is two rows on one line.
        text.split(TWO_ROWS).each { |part| add_item(part) }
        @plan[:last_line] = index
      elsif @plan[:accepting] && (credits = stripped[ONLY_CREDITS, 1]) && @plan[:semester_items].last&.min_credits.nil?
        # "(1 credit)" on its own line ends the row above it.
        last = @plan[:semester_items].pop
        @plan[:semester_items] << last.with(min_credits: credits.to_i, max_credits: credits.to_i)
      else
        # A row after text in a semester. When the plan goes on after it,
        # the text cut the rows of the semester in two.
        @plan[:orphan] ||= stripped if !@plan[:accepting] && item_line?(stripped)
        @plan[:accepting] = false
        @plan[:prose] += 1
        @plan[:interrupted] = true if heading?(stripped)
        close_plan if @plan[:prose] > PROSE_LIMIT
      end
      index + 1
    end

    def start_semester(index, match)
      key = [ PdfCatalog::YEAR_WORDS.fetch(match[1].downcase), PdfCatalog::SEASONS.index(match[2].downcase) ]
      if @plan && key.<=>(@plan[:key]).positive?
        if @plan[:interrupted] || @plan[:orphan]
          @plan[:invalid] ||= @plan[:interrupted] ? "a program name between two semesters" : "text between the rows of a semester, before: #{@plan[:orphan]}"
          close_plan
        else
          close_semester
          open_semester(key, match[3], index)
          return
        end
      end

      close_plan
      # A plan starts in the fall of the first year. A part of a plan that
      # starts later, such as a concentration's own semesters, is left out.
      if key == [ 1, 0 ]
        @fragment_reported = false
        @plan = { heading: heading_before(index), line: index + 1, items: [], warnings: [], prose: 0,
                  interrupted: false, invalid: nil }
        open_semester(key, match[3], index)
      elsif !@fragment_reported
        @fragment_reported = true
        @rejections << PdfCatalog::Rejection.new(heading: nil, line: index + 1,
                                                 reason: "semesters that do not start in the first year")
      end
    end

    # A total such as "18-19" is a range, which the check cannot use.
    # last_line is the last heading or row of the plan. The program name of
    # the next plan is after it.
    def open_semester(key, total, index)
      total = total.to_s.match?(/\A\d+\z/) ? total.to_i : nil
      @plan.merge!(key: key, total: total, semester_items: [], accepting: true, prose: 0, orphan: nil, last_line: index)
    end

    def close_semester
      items = @plan[:semester_items]
      if @plan[:total] && items.any? && items.all?(&:min_credits)
        sum = items.sum(&:min_credits)
        if sum != @plan[:total]
          year, season = @plan[:key]
          @plan[:warnings] << "Year #{year} #{PdfCatalog::SEASONS[season]}: the rows add up to #{sum} credits, " \
                              "the printed total is #{@plan[:total]}."
        end
      end
      @plan[:items].concat(items)
    end

    def close_plan
      return if @plan.nil?

      close_semester
      plan = @plan
      @plan = nil
      reason = plan[:invalid]
      reason ||= "no program name above the plan" if plan[:heading].nil?
      reason ||= "no rows" if plan[:items].empty?
      if reason
        @rejections << PdfCatalog::Rejection.new(heading: plan[:heading], line: plan[:line], reason: reason)
      else
        @plans << PdfCatalog::Plan.new(heading: plan[:heading], line: plan[:line], items: plan[:items],
                                       warnings: plan[:warnings])
      end
      @last_end = plan[:last_line]
    end

    def add_item(text)
      attributes = read_item(text)
      if attributes.nil?
        @plan[:invalid] ||= "cannot read the row #{text}"
        return
      end

      year, season = @plan[:key]
      @plan[:semester_items] << PdfCatalog::Item.new(year_index: year, season: PdfCatalog::SEASONS[season], **attributes)
    end

    def read_item(text)
      text, credits = PdfRowReader.split_credits(text)
      codes = text.scan(PdfRowReader::CODE)
      attributes =
        if text.match?(/\bor\b/i) && text.match?(/\A#{PdfRowReader::CODE.source}/)
          # "MATH1750, Engineering Calculus I or MATH1775 Applications of
          # Calculus" is a choice. "ARCH8750, Concentration Studies OR
          # ELECTIVE, Architecture" is a slot that names both.
          if codes.size >= 2
            PdfRowReader.choice(codes)
          else
            { kind: "placeholder", subject_code: nil, course_number: nil, title: nil,
              label: PdfRowReader.clean_title(text), options: [] }
          end
        elsif (match = text.match(COURSE))
          PdfRowReader.read("#{match[1]}#{match[2]}", match[3])
        elsif text.match?(SLOT)
          PdfRowReader.read(text, "")
        elsif (match = text.match(PLACEHOLDER))
          PdfRowReader.read(match[1], match[2])
        end
      attributes&.merge(min_credits: credits, max_credits: credits)
    end

    def item_line?(text)
      text = text.sub(BULLET, "")
      text.match?(COURSE) || text.match?(SLOT) || text.match?(PLACEHOLDER)
    end

    def heading?(text)
      text.length <= HEADING_LIMIT && text.match?(HEADING) && !item_line?(text)
    end

    # The program name is the last name-like line between the plan before
    # and this one.
    def heading_before(index)
      (index - 1).downto(@last_end + 1) do |i|
        text = squish(@lines[i])
        return text if heading?(text)
      end
      nil
    end

    def next_content(index)
      index += 1 while index < @lines.size && squish(@lines[index]).then { |text| text.empty? || text.match?(PdfCatalog::FOOTER) }
      index < @lines.size ? index : nil
    end

    def squish(text) = text.to_s.gsub(/[[:space:]]+/, " ").strip
  end
end
