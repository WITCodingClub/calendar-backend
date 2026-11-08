# frozen_string_literal: true

module DegreeRequirements
  module PdfCatalog
    # Finds the DegreeProgram of a plan from a PDF. The PDFs name a program
    # as "COMPUTER NETWORKING (BSCN)" or "Computer Science Bachelor of
    # Science", and the HTML catalog as "Computer Science, B.S.". The
    # matcher compares the subject words and the kind (bachelor, master,
    # concentration). A plan with no match, or more than one, is left out:
    # the import does not make a DegreeProgram for it, so a typo in a PDF
    # does not add a program.
    #
    # The programs come from the HTML years (2019-2020 and later), so a
    # program that closed before 2019 has no DegreeProgram and is left out.
    class ProgramMatcher
      # Names in the PDFs that differ from the catalog name of the same
      # program, as subject words.
      RENAMED = {
        "engineering interdisciplinary" => "engineering",
        "facility planning and management" => "facility management"
      }.freeze

      DEGREE_WORDS = /
        \bwith\s+a\s+concentration\s+in\b | \bcurriculum\s+for\b | \bbachelor\s+of\s+science(?:\s+degree)? | \bmaster\s+of\s+science |
        \bmasters?\s+degree | \bb\.\s?s\.? | \bm\.\s?s\.? | \bm\.\s?arch\.? |
        \bconcentration\b | \bminor\b | \bcertificate\b | \bprofessional\b
      /xi

      def initialize(programs = DegreeProgram.all.to_a)
        @by_key = programs.group_by { |program| [ self.class.subject(program.name), program.kind ] }
        @by_subject = programs.group_by { |program| self.class.subject(program.name) }
      end

      # The DegreeProgram for a PdfCatalog::Program, or nil.
      def call(pdf_program)
        title = pdf_program.title.to_s
        return nil if title.blank?

        subject = self.class.subject(title)
        subject = RENAMED.fetch(subject, subject)
        kind = self.class.kind(title, pdf_program.code)
        candidates = kind ? @by_key.fetch([ subject, kind ], []) : @by_subject.fetch(subject, [])
        candidates.first if candidates.one?
      end

      # "Computer Science, B.S." and "COMPUTER SCIENCE (BCOS)" give
      # "computer science". "Architecture, B.S. - Urbanism Concentration"
      # and "ARCHITECTURE – URBANISM CONCENTRATION" give "architecture urbanism".
      def self.subject(name)
        name.to_s.downcase.sub(/\bmaster\s+of\s+architecture\b/, "architecture").gsub(/\([a-z ]{2,7}\)/, " ").gsub(DEGREE_WORDS, " ").gsub("&", " and ")
            .gsub(/\(.*?\)/, " ").gsub(/[^a-z0-9]+/, " ").squeeze(" ").strip
      end

      # The kind from the name or the program code: BSCN and BCOS are
      # bachelor's degrees, MSCM and MARC master's degrees.
      def self.kind(name, code)
        case name
        when /concentration/i then "concentration"
        when /\bminor\b/i then "minor"
        when /certificate/i then "certificate"
        when /bachelor|\bB\.S\./i then "bachelor"
        when /master/i then "master"
        else
          case code.to_s
          when /\AB/ then "bachelor"
          when /\AM/ then "master"
          end
        end
      end
    end
  end
end
