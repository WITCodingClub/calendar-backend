# frozen_string_literal: true

module Admin
  # The courses around one section, for the admin course page: the
  # prerequisite tree, the corequisites, the mutual exclusions, the courses it
  # is a prerequisite for, the sections a student registers with it, and the
  # sections it is cross-listed with.
  #
  # A prerequisite names a course, not a section. section_for gives a section
  # of that course to link to: one in the same term first, else the newest.
  class CourseRelations
    attr_reader :course

    def initialize(course)
      @course = course
    end

    def catalog_course
      return @catalog_course if defined?(@catalog_course)

      @catalog_course = course.catalog_course
    end

    # The tree from CatalogCourse#prerequisites, or nil.
    def prerequisites
      catalog_course&.prerequisites
    end

    # [{ "subject_code" => "COMP", "course_number" => 1050 }, ...]
    def corequisites
      catalog_course&.corequisites || []
    end

    # [{ "subject_code" => "ARCH", "course_number" => 5100, "level" => ..., "min_grade" => ... }, ...]
    def mutual_exclusions
      catalog_course&.mutual_exclusions || []
    end

    # The CatalogCourse rows that list this course as a prerequisite.
    def unlocks
      @unlocks ||= catalog_course ? catalog_course.unlocks.distinct.order(:subject_code, :course_number).to_a : []
    end

    # Each group is one set of partner sections (Catalog::SectionLinks).
    def linked_options
      @linked_options ||= Catalog::SectionLinks.new(course).options
    end

    # The other sections in this section's cross-list group, by CRN.
    def cross_listed_sections
      @cross_listed_sections ||= Course.where(term_id: course.term_id, crn: course.cross_listed_crns).order(:crn).to_a
    end

    def section_for(subject_code, course_number)
      sections[[ subject_code.to_s.upcase, course_number.to_i ]]
    end

    private

    # Every named course in one query, keyed by [code, number].
    def sections
      @sections ||= begin
        pairs = codes.uniq
        if pairs.empty?
          {}
        else
          conditions = pairs.map do |code, number|
            Course.sanitize_sql_array(CourseCode.subject_condition("courses.subject", [ code ])) +
              Course.sanitize_sql_array([ " AND courses.course_number = ?", number ])
          end
          same_term = ActiveRecord::Base.sanitize_sql_array([ "courses.term_id = ? DESC", course.term_id ])

          Course.joins(:term)
                .where(conditions.map { |condition| "(#{condition})" }.join(" OR "))
                .order(Arel.sql(same_term), Arel.sql("terms.start_date DESC NULLS LAST"), "terms.year DESC", :section_number)
                .each_with_object({}) { |section, map| map[[ section.prefix, section.course_number ]] ||= section }
        end
      end
    end

    def codes
      refs = PrerequisiteTree.new(prerequisites).courses + corequisites + mutual_exclusions
      refs.map { |ref| [ ref["subject_code"].to_s.upcase, ref["course_number"].to_i ] } +
        unlocks.map(&:key)
    end
  end
end
