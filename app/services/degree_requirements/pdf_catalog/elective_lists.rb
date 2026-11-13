# frozen_string_literal: true

module DegreeRequirements
  module PdfCatalog
    # Reads the elective lists that a program prints near its plan of study
    # in a catalog PDF (#962), and links each slot of the plan to its list.
    # The PDFs print a list as prose with course rows under it:
    #
    #   Networking and Security Electives
    #   Computer Networking students take a total of five major electives.
    #   ... The Computer Networking Elective courses may include:
    #
    #   COMP2000                Data Structures
    #   COMP2350                Algorithms
    #
    #   CONSTRUCTION MANAGEMENT ELECTIVES
    #   Students take two of the following four electives ...:
    #   CMGT820                      Conflict Resolution & Negotiation for CM
    #
    # A list is a run of lines that start with a course code, outside every
    # plan. A line can hold two codes in two columns. A line with no code
    # inside the run is the rest of a title or a sub-heading ("Emerging
    # Technologies"), unless it starts a new list ("... from the following
    # list:"). The name of a list is the last "<Words> Elective(s)" phrase
    # in the text just above it, and its minimum comes from the last lines
    # ("Select one course from the following list").
    #
    # A plan takes only the lists that one of its slots names, nearest
    # first, and only the lists that no other program's plan separates from
    # it (reachable?). A slot that SharedElectives links (HSS, English, co-op, free)
    # is left to it. A list no slot names is not kept: the text around the
    # plans also holds minors and concentrations.
    class ElectiveLists
      Group = ProgramPageParser::Group
      GroupCourse = ProgramPageParser::GroupCourse

      # A course code at the start of a line or of a column: "COMP2000",
      # "COMP 2000", "• PHYS310", "ARCH590".
      CODE = /(?:\A\s*|\s{2,}|\t)(?:[•·▪]\s*)?([A-Z]{2,5}) ?(\d{3,4})[A-Z]?\b/
      ROW = /\A\s*(?:[•·▪]\s*)?[A-Z]{2,5} ?\d{3,4}[A-Z]?\b/
      # Page footers inside a list: "176", "2013-2014 Academic Catalog 87 Rev 12 Feb 2015".
      FOOTER = /\A\s*\d{1,3}\s*\z|Academic Catalog/
      # A line with no code that starts a new list, not the rest of a row.
      LIST_START = /:\s*\z|\b(?:select|choose|following|may include|electives?|courses|credits)\b/i
      # "Computer Networking Elective", "CONSTRUCTION MANAGEMENT ELECTIVES",
      # "Math or Science Electives": capitalized words before "Elective(s)".
      NAME = %r{((?:(?!(?i:electives?)\b)[A-Z][\w/&'’-]*\s+(?:(?:and|or|of|&)\s+)?){1,5})(?i:electives?)\b}
      # Words that start a sentence, not a name.
      LEADING_WORDS = /\A(?:(?:The|A|An|All|Any|Two|Three|Four|Five|Six|These|This|Each|One|Of|Other|Some|Select|Choose|Students?|Take)\s+)+/
      SEMESTER = /\b(?:Fall|Spring|Summer)\s+Semester\b|\bFirst Year\b/
      # How far above a list its name can be.
      CONTEXT_LINES = 15
      # A running line of text is longer than a row.
      PROSE_LENGTH = 70
      # A row of a plan: "Elective   Technical Elective (4 credits)".
      PLAN_ROW = /\A(?:Electives?|[A-Z]{2,5} ?\d{3,4}[A-Z]?)\s+.*\(\d{1,2} credits?\)\s*\z/i
      # The longest paragraph that is only a sub-heading over a list.
      SUB_HEADING_LINES = 2
      # Lines with no code in a row inside a list: a title that runs on, then
      # a sub-heading.
      CONTINUATION_LINES = 3
      # "(all courses are 4 credits unless otherwise noted)" is not a minimum.
      COURSE_CREDITS = /all courses are \S+ (?:\(\d+\) )?credits?/i
      # How far a list can be from the plan it belongs to.
      MAX_DISTANCE = 300
      # The most lines between two plans of one run (see reachable?).
      PLAN_RUN_GAP = 60
      # "The Advanced Security Elective courses may include: COMP3800".
      MIN_COURSES = 1

      def self.call(text, programs) = new(text, programs).call

      def initialize(text, programs)
        @lines = text.to_s.split("\n").map { |line| line.delete("\f") }
        @programs = programs
        @spans = programs.filter_map(&:lines).uniq
        @plan_lines = Set.new(@spans.flat_map(&:to_a))
      end

      # The programs, each with its lists and its slots linked to them.
      def call
        lists = find_lists
        @programs.map { |program| program.lines ? link(program, lists) : program }
      end

      private

      def link(program, lists)
        span = program.lines
        # Nearest first. At the same distance, a list after the plan wins:
        # most programs print their lists under the plan.
        near = lists.map { |list| [ list, distance(list, span) ] }
                    .select { |list, gap| gap <= MAX_DISTANCE && reachable?(list, span) }
                    .sort_by { |list, gap| [ gap, list[:end] < span.begin ? 1 : 0 ] }.map(&:first)
        return program if near.empty?

        # A list with the name of a shared list ("Humanities Electives") is
        # not kept: SharedElectives would take it for its own list.
        groups = near.map { |list| list[:group] }.reject { |group| SharedElectives.rule_for(group.name) }
        return program if groups.empty?

        plan = program.plan.with(items: program.plan.items.map { |item| shared?(item) ? item : item.with(group_index: nil) })
        linked = PlaceholderLinker.call([ plan ], groups).first
        linked = linked.with(items: linked.items.zip(plan.items).map { |item, before| shared?(before) ? before : item })

        used = linked.items.filter_map(&:group_index).uniq.sort
        return program if used.empty?

        items = linked.items.map { |item| item.group_index ? item.with(group_index: used.index(item.group_index)) : item }
        program.with(plan: linked.with(items: items), groups: used.map { |i| groups[i] })
      end

      # A list reaches a plan when no other plan is between them, or when
      # the plans between them form one run with the plan, each at most
      # PLAN_RUN_GAP lines from the next: the architecture plans print one
      # list under the last of them. A program description is longer, so the
      # plan of another program does not pass on its list.
      def reachable?(list, span)
        after = list[:start] > span.end
        between = @spans.select { |other| after ? other.begin > span.end && other.end < list[:start] : other.end < span.begin && other.begin > list[:end] }
        return true if between.empty?

        chain = ([ span ] + between).sort_by(&:begin)
        chain.each_cons(2).all? { |first, second| second.begin - first.end <= PLAN_RUN_GAP }
      end

      # A slot that SharedElectives links, or not a slot.
      def shared?(item) = item.kind != "placeholder" || SharedElectives.rule_for(item.label).present?

      def distance(list, span)
        if list[:end] < span.begin then span.begin - list[:end]
        elsif list[:start] > span.end then list[:start] - span.end
        else 0
        end
      end

      # -- Lists ---------------------------------------------------------------

      def find_lists
        lists = []
        index = 0
        while index < @lines.size
          if row?(index)
            list, index = read_list(index, lists.last&.dig(:end))
            next if list.nil?

            # "In addition, BSCN students may use ... as Advanced Networking
            # Elective courses": a second part of the list before it.
            if (last = lists.last) && last[:group].name == list[:group].name && list[:start] - last[:end] <= CONTEXT_LINES &&
               no_plan_between?(last[:end], list[:start])
              courses = (last[:group].courses + list[:group].courses).uniq { |c| [ c.subject_code, c.course_number ] }
              lists[-1] = last.merge(end: list[:end], group: last[:group].with(courses: courses))
            else
              lists << list
            end
          else
            index += 1
          end
        end
        lists
      end

      def no_plan_between?(from, to) = (from..to).none? { |index| @plan_lines.include?(index) }

      # A line that starts with a code and is not a sentence. "BMED260
      # Physiology for Engineers I, BMED460 Physiology for Engineers II, and
      # BMED660 Biomedical" runs across the page with single spaces.
      def row?(index)
        line = @lines[index]
        !@plan_lines.include?(index) && line.match?(ROW) && !(line.strip.size > PROSE_LENGTH && !line.match?(/\S\s{3,}\S|\t/))
      end

      # The list that starts at `start`, and the index of the line after it.
      def read_list(start, previous_end)
        codes = []
        index = start
        last_row = start
        while index < @lines.size && !@plan_lines.include?(index)
          line = @lines[index]
          if row?(index)
            codes.concat(line.scan(CODE).map { |subject, number| [ subject, number.to_i ] })
            last_row = index
          elsif !skippable?(line) && !continues_to_row?(index)
            break
          end
          index += 1
        end

        codes.uniq!
        return [ nil, last_row + 1 ] if codes.size < MIN_COURSES

        context = context_before(start, previous_end)
        # A plan that no parser reads: "Elective   Technical Elective (4 credits)"
        # over "MATH1005   Math A (3 credits)".
        return [ nil, last_row + 1 ] if context.last&.last.to_s.match?(PLAN_ROW)

        group = group_for(context, codes)
        [ group && { start: start, end: last_row, group: group }, last_row + 1 ]
      end

      def skippable?(line) = line.strip.empty? || line.match?(FOOTER)

      # A line with no code that is the rest of a title or a sub-heading.
      def continues?(line) = !line.match?(LIST_START) && !line.strip.end_with?(".")

      # Is the line at `index`, with no code, part of the list? The rest of
      # a title and a sub-heading are, when a row comes after them: "Design"
      # then "Representation" then "ARCH590 Color".
      def continues_to_row?(index)
        CONTINUATION_LINES.times do
          return false unless continues?(@lines[index])

          index += 1
          index += 1 while index < @lines.size && skippable?(@lines[index])
          return false if index >= @lines.size || @plan_lines.include?(index)
          return true if @lines[index].match?(ROW)
        end
        false
      end

      # The paragraphs of text above a list, nearest last, up to a plan, a
      # semester heading, or the list before it. A blank line ends a
      # paragraph.
      def paragraphs_before(start, previous_end)
        paragraphs = [ [] ]
        index = start - 1
        while index >= 0 && paragraphs.sum(&:size) < CONTEXT_LINES
          break if @plan_lines.include?(index) || (previous_end && index <= previous_end)

          line = @lines[index]
          break if line.match?(SEMESTER)

          if line.strip.empty?
            paragraphs.unshift([]) if paragraphs.first.any?
          elsif !line.match?(FOOTER)
            paragraphs.first.unshift(line.strip.squeeze(" "))
          end
          index -= 1
        end
        paragraphs.reject(&:empty?)
      end

      # The text that names a list: the paragraph just above it. When that
      # paragraph is a short sub-heading ("Urbanism/Adaptive Interventions"
      # under "Architecture Electives are listed by concentration"), the
      # paragraph or heading line above it can name the list. Text further
      # up is about something else: "*** Science Elective" over a
      # paragraph, then "Minor in Computer Networking ... Core Courses".
      def context_before(start, previous_end)
        paragraphs = paragraphs_before(start, previous_end)
        intro = paragraphs.last || []
        named = intro if name_of(intro)
        named ||= paragraphs[-2] if intro.size <= SUB_HEADING_LINES && paragraphs[-2] && name_of(paragraphs[-2])
        [ named, intro ]
      end

      def group_for((named, intro), codes)
        name = named && name_of(named)
        return nil if name.nil?

        min_courses, min_credits = ProgramPageParser.minimum(intro.last(2).join(" ").gsub(COURSE_CREDITS, ""))
        Group.new(name: name, heading: intro.join(" ").truncate(500), min_courses: min_courses,
                  min_credits: min_credits, notes: nil, plan_index: nil,
                  courses: codes.map { |subject, number| GroupCourse.new(subject_code: subject, course_number: number, requires_approval: false) })
      end

      # The last "<Words> Elective(s)" phrase in the lines. "The Computer
      # Networking Elective courses may include" names "Computer Networking
      # Electives". "the Department's elective" names none.
      def name_of(lines)
        phrase = lines.join(" ").scan(NAME).map(&:first).reverse_each.lazy
                      .reject { |words| words.match?(/['’]s\b/) }
                      .map { |words| clean_name(words) }.find(&:present?)
        return nil if phrase.nil?
        words = phrase.squeeze(" ")
        # "CONSTRUCTION MANAGEMENT" reads "Construction Management". A short
        # code stays: "CRES Electives".
        if words == words.upcase && words.split.any? { |word| word.size > 5 }
          words = words.split.map { |word| word.match?(/\A(?:and|or|of)\z/i) ? word.downcase : word.capitalize }.join(" ")
        end
        "#{words} Electives".truncate(ProgramPageParser::NAME_LIMIT, separator: " ")
      end

      # The words of a name without the start of a sentence, a semester
      # ("Semester Two"), a code ("MATH1850"), a numeral ("III"), or a piece
      # of the word elective that Word broke over lines ("ELECTI").
      def clean_name(words)
        words = words.sub(LEADING_WORDS, "").sub(/\ASemester\s+\w+\s+/, "").split
                     .reject { |word| word.match?(/\d|\A[IVX]+\z|\A(?:elec|lective)/i) }.join(" ")
        words if words.match?(/[A-Za-z]{3,}/)
      end
    end
  end
end
