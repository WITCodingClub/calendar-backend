# frozen_string_literal: true

module Catalog
  # Gives each stored section a subject label with the code at the end
  # (Catalog::SubjectLabels), and moves the CatalogCourse rows that were
  # seeded under a label to the real code.
  #
  # Before this fix, a section of a subject whose Banner label has no code
  # kept the bare label: "Building Construction", not "Building Construction
  # (BLDG)". Its CatalogCourse got the subject code "BUILDING CONSTRUCTION",
  # so the catalog year comparison listed BLDG 1100 as a course with no
  # section. Banner labels CPFM "Facilities Management (CPCE)", so CPFM
  # courses were seeded as CPCE. Sections that Catalog::Importer made and no sync touched kept the
  # bare code, "COMP". Those get the label too.
  #
  #   Catalog::SubjectLabelRepair.call # => { sections:, catalog_courses_moved:, catalog_courses_merged: }
  #
  # It sends one request to Banner for each term with sections.
  class SubjectLabelRepair
    def self.call(terms: Term.where(id: Course.select(:term_id)))
      new(terms).call
    end

    def initialize(terms)
      @terms = terms
    end

    def call
      sections = 0
      labels = {} # bad CatalogCourse subject code => real code

      @terms.find_each do |term|
        codes = SubjectLabels.codes(term.uid)
        next if codes.empty?

        descriptions = codes.invert
        term.courses.distinct.pluck(:subject).each do |subject|
          code = codes[subject.to_s.strip] || (descriptions.key?(subject.to_s.strip.upcase) && subject.to_s.strip.upcase)
          next unless code

          label = SubjectLabels.label(descriptions.fetch(code), code)
          next if label == subject

          old_codes(subject).each { |old| labels[old] = code }
          sections += term.courses.where(subject: subject).update_all(subject: label, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        end
      end

      moved, merged = move_catalog_courses(labels.reject { |bad, code| bad == code })
      CourseDetailsSync.link_degree_requirements

      { sections: sections, catalog_courses_moved: moved, catalog_courses_merged: merged }
    end

    private

    # The codes the old readers took from a label: the whole label, or the
    # last parentheses, so "Graduate Internship (optional)" gave "OPTIONAL"
    # and "Facilities Management (CPCE)" gave "CPCE".
    def old_codes(subject)
      subject = subject.to_s.strip
      [ subject.upcase, subject[/\(([^)]+)\)\s*\z/, 1]&.strip&.upcase ].compact
    end

    # A row under a bad code takes the real code. When a row with the real
    # code already exists, the bad row is deleted: its links are by code, and
    # the next CourseDetailsSync seeds anything it misses.
    def move_catalog_courses(labels)
      moved = merged = 0
      CatalogCourse.where(subject_code: labels.keys).find_each do |course|
        code = labels.fetch(course.subject_code)
        if CatalogCourse.exists?(subject_code: code, course_number: course.course_number)
          course.destroy!
          merged += 1
        else
          course.update!(subject_code: code)
          moved += 1
        end
      end
      [ moved, merged ]
    end
  end
end
