# frozen_string_literal: true

module DegreeRequirements
  # Reads one plan row of a PDF catalog from its code cell and its title:
  # "COMP1000" and "Computer Science I" is a course, "ELECTIVE" and
  # "Humanities or Social Science" is a placeholder. Returns nil for a cell
  # that it cannot read, so the parser leaves the plan out.
  module PdfRowReader
    CODE = /([A-Z]{2,5}) ?(\d{3,4})/
    ONE_CODE = /\A#{CODE.source}\z/
    # Two or more codes with "or" between them: "MATH1750 or MATH1850".
    CHOICE = /\A#{CODE.source}(?:,?\s+or\s+#{CODE.source})+\z/i
    # "See ENGL/HSS note below *" and "see ** below" point to a note.
    SEE_NOTE = /[,.;]?\s*\(?\bsee\b.*\z/i
    CREDITS = /[,(]?\s*(\d{1,2})\s*(?:credits?|cr)\.?\s*\)?\s*\z/i

    module_function

    # Returns the attributes of a PdfCatalog::Item without the year, season,
    # and credits.
    def read(cell, title)
      cell = squish(cell)
      title = clean_title(title)
      return nil if cell.empty?

      if (match = cell.match(ONE_CODE))
        { kind: "course", subject_code: match[1], course_number: match[2].to_i, title: title.presence, label: nil,
          options: [] }
      elsif cell.match?(CHOICE)
        choice(cell.scan(CODE), title)
      elsif cell.match?(/\d/)
        # A code in a shape the reader does not know, such as "COMP128/285".
        nil
      else
        { kind: "placeholder", subject_code: nil, course_number: nil, title: nil,
          label: placeholder_label(cell, title), options: [] }
      end
    end

    def choice(codes, title = nil)
      { kind: "choice", subject_code: nil, course_number: nil, title: title.presence, label: nil,
        options: codes.map { |subject, number| { "subject_code" => subject, "course_number" => number.to_i } } }
    end

    # Splits "Studio 01 (6 credits)" into the text and the credits.
    def split_credits(text)
      text = squish(text)
      match = text.match(CREDITS)
      return [ text, nil ] if match.nil?

      [ text[0...match.begin(0)].strip.delete_suffix(","), match[1].to_i ]
    end

    def clean_title(text)
      squish(text).sub(SEE_NOTE, "").delete_suffix(",").strip
    end

    def placeholder_label(cell, title)
      title = title.delete("*").strip
      return title if title.match?(/elective/i)
      # "ENGLISH, Sequence" is the English Sequence.
      return "#{cell.capitalize} #{title}" if title.present? && cell.match?(/\A[A-Z]+\z/) && cell.length > 3 &&
                                              !title.downcase.include?(cell.downcase) && cell != "ELECTIVE"
      return "#{title} Elective" if title.present? && cell.match?(/\AELECTIVE\z/i)
      return title if title.present?

      cell.split.map { |word| word.length <= 3 ? word.upcase : word.capitalize }.join(" ")
    end

    def squish(text) = text.to_s.gsub(/[[:space:]]+/, " ").strip
  end
end
