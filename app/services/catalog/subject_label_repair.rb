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
  # courses were seeded as CPCE. Sections that Catalog::Importer made and no
  # sync touched kept the bare code, "COMP". Those get the label too.
  #
  #   Catalog::SubjectLabelRepair.call # => { sections:, catalog_courses_moved:, catalog_courses_merged: }
  #
  # It sends one request to Banner for each term with sections. The bad codes
  # come from Banner's subject lists, not from the stored sections, so a run
  # after a failed run still moves every row.
  class SubjectLabelRepair
    def self.call(terms: Term.where(id: Course.select(:term_id)))
      new(terms).call
    end

    def initialize(terms)
      @terms = terms
    end

    def call
      sections = 0
      bad_codes = {} # bad CatalogCourse subject code => real code
      real_codes = Set.new

      @terms.find_each do |term|
        codes = SubjectLabels.codes(term.uid)
        next if codes.empty?

        real_codes.merge(codes.values)
        codes.each { |description, code| old_codes(description).each { |old| bad_codes[old] ||= code } }
        sections += relabel(term, codes)
      end

      moved, merged = move_catalog_courses(bad_codes.reject { |bad, _| real_codes.include?(bad) })
      CourseDetailsSync.link_degree_requirements

      { sections: sections, catalog_courses_moved: moved, catalog_courses_merged: merged }
    end

    private

    # The sections of one term whose label is not Banner's label with the
    # real code. Each changed section marks its students for a calendar sync,
    # as an update through the model does (CourseChangeTrackable): the
    # subject is in the event's course code.
    def relabel(term, codes)
      descriptions = codes.invert
      changed = 0

      term.courses.distinct.pluck(:subject).each do |subject|
        stripped = subject.to_s.strip
        code = codes[stripped] || (descriptions.key?(stripped.upcase) && stripped.upcase)
        next unless code

        label = SubjectLabels.label(descriptions.fetch(code), code)
        next if label == subject

        scope = term.courses.where(subject: subject)
        ids = scope.ids
        changed += scope.update_all(subject: label, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        CourseCalendars::SyncMarker.mark(ids)
      end
      changed
    end

    # The codes the old readers took from a Banner label that has no code or
    # a wrong one: the whole label, or the last parentheses. "Graduate
    # Internship (optional)" gave "GRADUATE INTERNSHIP (OPTIONAL)" or
    # "OPTIONAL", and "Facilities Management (CPCE)" gave "CPCE".
    def old_codes(description)
      description = description.to_s.strip
      [ description.upcase, description[/\(([^)]+)\)\s*\z/, 1]&.strip&.upcase ].compact.uniq
    end

    # A row under a bad code takes the real code. When a row with the real
    # code already exists, the bad row is deleted: its links are by code, and
    # link_degree_requirements links them to the real row.
    def move_catalog_courses(bad_codes)
      moved = merged = 0
      CatalogCourse.where(subject_code: bad_codes.keys).find_each do |course|
        code = bad_codes.fetch(course.subject_code)
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
