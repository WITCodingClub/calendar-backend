# frozen_string_literal: true

module Catalog
  # The courses around one section, for the admin course page: the
  # prerequisite tree, the corequisites, the courses it is a prerequisite for,
  # and the sections a student registers with it.
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

      @catalog_course = CatalogCourse.find_by(subject_code: course.prefix, course_number: course.course_number)
    end

    # The tree from CatalogCourse#prerequisites, or nil.
    def prerequisites
      catalog_course&.prerequisites
    end

    # [{ "subject_code" => "COMP", "course_number" => 1050 }, ...]
    def corequisites
      catalog_course&.corequisites || []
    end

    # The CatalogCourse rows that list this course as a prerequisite.
    def unlocks
      @unlocks ||= catalog_course ? catalog_course.unlocks.distinct.order(:subject_code, :course_number).to_a : []
    end

    # Each group is one set of partner sections (Catalog::SectionLinks).
    def linked_options
      @linked_options ||= SectionLinks.new(course).options
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
          clauses = pairs.map { "((courses.subject = ? OR courses.subject ILIKE ?) AND courses.course_number = ?)" }.join(" OR ")
          binds   = pairs.flat_map { |code, number| [ code, "%(#{code})", number ] }
          same_term = ActiveRecord::Base.sanitize_sql_array([ "courses.term_id = ? DESC", course.term_id ])

          Course.joins(:term)
                .where(clauses, *binds)
                .order(Arel.sql(same_term), Arel.sql("terms.start_date DESC NULLS LAST"), "terms.year DESC", :section_number)
                .each_with_object({}) { |section, map| map[[ section.prefix.upcase, section.course_number ]] ||= section }
        end
      end
    end

    def codes
      refs = course_refs(prerequisites) + corequisites
      refs.map { |ref| [ ref["subject_code"].to_s.upcase, ref["course_number"].to_i ] } +
        unlocks.map { |unlocked| [ unlocked.subject_code, unlocked.course_number ] }
    end

    def course_refs(node)
      return [] if node.nil?
      return [ node ] if node["type"] == "course"

      Array(node["operands"]).flat_map { |operand| course_refs(operand) }
    end
  end
end
