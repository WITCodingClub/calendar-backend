# frozen_string_literal: true

module DegreeRequirements
  module PdfCatalog
    # Turns one plan cell of a PDF ("COMP128", "Computer Science I", 4) into
    # plan rows of the same shape as the HTML import (ProgramPageParser::Item).
    module ItemBuilder
      Item = ProgramPageParser::Item

      # A code with an optional space: "COMP128", "COMP 1000", "MATH1776A".
      COURSE = /\A([A-Z]{2,5}) ?(\d{3,4})[A-Z]?\z/
      # The first line of a placeholder: ELECTIVE, ENGLISH, HSS ELECTIVE.
      # Other upper-case lines are headings ("FACULTY") or titles ("MATLAB").
      PLACEHOLDER = %r{\A(?:[A-Z][A-Z&/-]* ){0,3}(?:ELECTIVES?|ENGLISH)\z}
      # Words that stay upper case in a placeholder label.
      ACRONYMS = %w[HSS ENGL STEM GE].freeze

      module_function

      # Is `text` the first line of a plan cell?
      def code?(text)
        text = clean_code(text)
        text.match?(COURSE) || choice_codes(text).present? || both_codes(text).present? ||
          text.match?(PLACEHOLDER)
      end

      # The rows for one cell. `code` is its first line and `title` the rest.
      # `credits` is a number or a range such as "3-4".
      def build(code, title, credits, year_index:, season:)
        # "ELECTIVE*" points to a note under the plan.
        footnote = "*" if code.to_s.strip.delete_suffix(",").end_with?("*")
        code = clean_code(code)
        title = title.to_s.gsub(/[[:space:]]+/, " ").strip
        min, max = credits.to_s.scan(/\d+/).map(&:to_i).values_at(0, -1)
        base = { year_index: year_index, season: season, footnote: footnote, group_index: nil, options: [],
                 min_credits: min, max_credits: max }

        if (match = COURSE.match(code))
          [ Item.new(**base, kind: "course", subject_code: match[1], course_number: match[2].to_i, label: title.presence) ]
        elsif (codes = choice_codes(code))
          options = codes.map { |subject, number| { "subject_code" => subject, "course_number" => number } }
          [ Item.new(**base, kind: "choice", subject_code: nil, course_number: nil, options: options, label: title.presence) ]
        elsif (codes = both_codes(code))
          # The credits are for the pair, as in the HTML import.
          codes.map do |subject, number|
            Item.new(**base, kind: "course", subject_code: subject, course_number: number, label: title.presence,
                             min_credits: nil, max_credits: nil)
          end
        else
          [ Item.new(**base, kind: "placeholder", subject_code: nil, course_number: nil, label: placeholder_label(code, title)) ]
        end
      end

      # "ELECTIVE" over "Humanities or Social Science" is a "Humanities or
      # Social Science Elective". "See ENGL/HSS note below" is not a label.
      def placeholder_label(code, title)
        text = title.sub(/,?\s*see\b.*\z/i, "").delete("*").strip
        name = code.split.map { |word| ACRONYMS.include?(word) ? word : word.capitalize }.join(" ")
        return name if text.blank?
        return text if text.match?(/elective|sequence/i) || !code.match?(/ELECTIVE/)

        "#{text} Elective"
      end

      # The sum of the minimum credits of the rows, or nil when no row has
      # credits. A pair of courses ("MATH1776 & MATH1777") has none.
      def total_credits(items)
        credits = items.filter_map(&:min_credits)
        credits.sum if credits.any?
      end

      def clean_code(text) = text.to_s.strip.delete_suffix(",").delete_suffix("*").delete_suffix(",").squeeze(" ")

      # "COMP1100 or COMP2100" or "COMP1000/ELEC3150".
      def choice_codes(text)
        parts = text.split(%r{\s+or\s+|\s*/\s*}i)
        codes_of(parts)
      end

      # "MATH1776 & MATH1777" takes both.
      def both_codes(text)
        codes_of(text.split(/\s*&\s*|\s+and\s+/i))
      end

      def codes_of(parts)
        return nil if parts.size < 2

        codes = parts.map { |part| COURSE.match(part.strip) }
        codes.all? ? codes.map { |m| [ m[1], m[2].to_i ] } : nil
      end
    end
  end
end
