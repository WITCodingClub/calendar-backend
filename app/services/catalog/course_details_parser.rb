# frozen_string_literal: true

module Catalog
  # Reads the HTML of Banner's course pages (LeopardWebClient.get_course_details)
  # into plain values for CatalogCourse.
  #
  # Banner shows prerequisites as rows of a table. Each row has a connector
  # (And, Or, or nothing on the first row), optional parentheses, and either a
  # test with a score or a course with a level and a minimum grade:
  #
  #   ( COMP 1050 Undergraduate TR
  #   Or COMP 1071 Undergraduate TR )
  #   And ( MATH 2300 Undergraduate TR )
  #
  # The rows become a tree. And binds tighter than Or, and parentheses group.
  class CourseDetailsParser
    TERMS = %w[fall spring summer].freeze

    # The tail of a description: "(4 credits) fall, spring". The term list is
    # optional, and Banner writes "credit" or "credits".
    CREDITS_TAIL = /\(\s*(?<credits>\d+)\s*credits?\s*\)\s*(?<terms>[a-z ,&]*)\z/i

    class << self
      # @return [Hash, nil] the prerequisite tree, or nil when there is none
      def prerequisites(html)
        tokens = prerequisite_rows(html).flat_map { |row| row_tokens(row) }
        return nil if tokens.empty?

        TreeBuilder.new(tokens).build
      end

      # @return [Array<Hash>] { subject_code:, course_number: } for each course
      def corequisites(html)
        table_rows(html).filter_map do |cells|
          subject = cells.find { |cell| subject_code(cell) }
          number  = cells.find { |cell| cell.match?(/\A\d{3,4}\z/) }
          { "subject_code" => subject_code(subject), "course_number" => number.to_i } if subject && number
        end
      end

      # @return [Hash] { description:, credit_hours:, typically_offered: }
      def description(html)
        text = clean_text(html)
        # The prerequisite sentence repeats the prerequisite table, so it is
        # dropped. The credits tail after it stays.
        text = text.sub(/\s*\bPrerequisites?:.*?(?=\(\s*\d+\s*credits?\s*\)|\z)/mi, " ").squish

        tail = CREDITS_TAIL.match(text)
        return { description: text.presence, credit_hours: nil, typically_offered: [] } unless tail

        {
          description:       text[0...tail.begin(0)].strip.presence,
          credit_hours:      tail[:credits].to_i,
          typically_offered: TERMS.select { |season| tail[:terms].downcase.include?(season) }
        }
      end

      # @return [Array<Hash>] { heading:, values: } for each group of restrictions
      def restrictions(html)
        doc = Nokogiri::HTML.fragment(html.to_s)
        groups = []

        doc.css("span").each do |span|
          text = span.text.squish
          next if text.blank?

          if span["class"].to_s.include?("status-bold")
            next if text.start_with?("Not all restrictions")

            groups << { "heading" => text.delete_suffix(":"), "values" => [] }
          elsif span["class"].to_s.include?("detail-popup-indentation") && groups.any?
            groups.last["values"] << text
          end
        end

        groups.reject { |group| group["values"].empty? }
      end

      # "Computer Science (COMP)" to "COMP".
      def subject_code(text)
        text.to_s[/\(([A-Z]{2,5})\)\s*\z/, 1]
      end

      private

      def prerequisite_rows(html)
        table_rows(Nokogiri::HTML.fragment(html.to_s).css("table.basePreqTable").to_html)
      end

      # Each body row of every table, as stripped cell texts.
      def table_rows(html)
        Nokogiri::HTML.fragment(html.to_s).css("tbody tr").map do |row|
          row.css("td").map { |cell| cell.text.squish }
        end
      end

      # Columns: And/Or, (, Test, Score, Subject, Course Number, Level, Grade, ).
      def row_tokens(cells)
        connector, open, test, score, subject, number, level, grade, close = cells
        tokens = []
        tokens << connector.downcase.to_sym if connector.present?
        open.to_s.count("(").times { tokens << :open }
        tokens << leaf(test, score, subject, number, level, grade)
        close.to_s.count(")").times { tokens << :close }
        tokens.compact
      end

      def leaf(test, score, subject, number, level, grade)
        if test.present?
          { "type" => "test", "name" => test, "score" => score.presence }
        elsif subject.present? && number.present?
          {
            "type"          => "course",
            "subject_code"  => subject_code(subject) || subject,
            "course_number" => number.to_i,
            "level"         => level.presence,
            "min_grade"     => grade.presence
          }
        end
      end

      def clean_text(html)
        # Banner escapes the <b> around the prerequisite sentence, so the
        # markup survives one round of parsing as text.
        once  = Nokogiri::HTML.fragment(html.to_s).text
        twice = Nokogiri::HTML.fragment(once).text
        twice.squish
      end
    end

    # Builds the prerequisite tree from tokens: leaves, :and, :or, :open, :close.
    # A missing connector between two leaves counts as and.
    class TreeBuilder
      def initialize(tokens)
        @tokens   = tokens
        @position = 0
      end

      def build
        node = parse_or
        simplify(node)
      end

      private

      def parse_or
        operands = [ parse_and ]
        while peek == :or
          advance
          operands << parse_and
        end
        operands.size == 1 ? operands.first : { "type" => "or", "operands" => operands }
      end

      def parse_and
        operands = [ parse_primary ]
        loop do
          if peek == :and
            advance
            operands << parse_primary
          elsif peek.is_a?(Hash) || peek == :open
            operands << parse_primary
          else
            break
          end
        end
        operands.compact!
        operands.size == 1 ? operands.first : { "type" => "and", "operands" => operands }
      end

      def parse_primary
        token = advance
        case token
        when :open
          node = parse_or
          advance if peek == :close
          node
        when Hash
          token
        end
      end

      def peek = @tokens[@position]

      def advance
        token = @tokens[@position]
        @position += 1
        token
      end

      # Flattens an and inside an and (or an or inside an or).
      def simplify(node)
        return node unless node.is_a?(Hash) && node["operands"]

        operands = node["operands"].compact.map { |operand| simplify(operand) }.flat_map do |operand|
          operand.is_a?(Hash) && operand["type"] == node["type"] ? operand["operands"] : [ operand ]
        end
        operands.size == 1 ? operands.first : node.merge("operands" => operands)
      end
    end
  end
end
