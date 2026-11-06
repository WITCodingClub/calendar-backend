# frozen_string_literal: true

module DegreeRequirements
  # Finds the DegreeProgram for the heading of a plan in a PDF catalog, such
  # as "COMPUTER SCIENCE (BCOS)" or "Master of Architecture (Two-Year)". The
  # programs come from the HTML catalogs, so a program that ended before
  # 2019-2020 has no match, and its plans are left out.
  #
  # It compares the subject only ("computer science") and takes the kind from
  # the Banner program code in the heading: BCOS is a bachelor, MSCM a
  # master. A heading with no code matches only when one program of a degree
  # kind has the subject. A concentration matches by its full name. A heading
  # with no match, or with more than one, gives nil.
  class PdfProgramMatcher
    Match = Data.define(:program, :plan_name)

    DEGREE_KINDS = %w[associate bachelor master].freeze
    # Words that name the degree, not the subject.
    DEGREE_WORDS = /\b(?:bachelor|master|associate)(?:'?s)?(?:\s+of(?:\s+(?:science|engineering|arts|applied\s+science))?)?(?:\s+degree)?\b|
                    \bb\s?s\b|\bm\s?s\b|\bdegree\b|\bcurriculum(?:\s+for)?\b|\bprogram\b|\bwith\s+concentration\s+in\b|
                    \bconcentration\b|\bminor\b|\bin\s+applied\s+science\b/x

    def initialize(programs = DegreeProgram.all)
      @by_key = programs.to_a.group_by { |program| [ program.kind, subject(program.name) ] }
    end

    def call(heading)
      text = heading.to_s.gsub(/[[:space:]]+/, " ").strip
      return nil if text.empty?

      codes = text.scan(/\(([A-Z]{2,5})(?:\[[^\]]*\])?\)/).flatten
      notes = text.scan(/\(([^)]*[a-z][^)]*)\)/i).flatten - codes
      candidates = candidates_for(text, codes.last)
      return nil unless candidates&.one?

      Match.new(program: candidates.first, plan_name: plan_name(notes))
    end

    private

    def candidates_for(text, code)
      if text.match?(/concentration/i)
        @by_key[[ "concentration", subject(text) ]]
      else
        kinds = kinds_for(text, code)
        kinds.flat_map { |kind| @by_key[[ kind, subject(text) ]] || [] }
      end
    end

    # BCOS, BSCM: bachelor. MSCM, MARC: master. A heading without a code
    # names its degree, or any degree kind may match.
    def kinds_for(text, code)
      return [ "master" ] if code&.start_with?("M") || text.match?(/\Amaster\b/i)
      return [ "bachelor" ] if code&.start_with?("B")
      return [ "associate" ] if code&.start_with?("A")

      DEGREE_KINDS
    end

    # "Construction Management Bachelor of Science - Facilities Management
    # Concentration" and "Construction Management (BSCM) with concentration
    # in Facilities Management" both give "construction management
    # facilities management".
    def subject(name)
      name.to_s.downcase.gsub("&", " and ").gsub(/\([^)]*\)/, " ").gsub(/[–—]/, "-")
          .gsub(DEGREE_WORDS, " ").gsub(/[^a-z0-9]+/, " ").squish
    end

    # "(One-Year)" or "(ONE YEAR)" names the plan of a program with more
    # than one plan, such as the Master of Architecture.
    def plan_name(notes)
      note = notes.find { |text| text.match?(/year/i) }
      note ? "#{note.tr('-', ' ').split.map(&:capitalize).join(' ')} Program" : "Plan of Study"
    end
  end
end
