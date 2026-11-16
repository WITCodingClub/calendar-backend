# frozen_string_literal: true

module Catalog
  # The prerequisite tree, the corequisites, and the mutual exclusions of one
  # CatalogCourse, each course with its code, its title, and whether WIT
  # Calendar knows it (linked). CourseSerializer and the GraphQL course and
  # section types read them here. Every course they name loads in one query.
  class CourseRequisites
    def initialize(catalog_course)
      @course = catalog_course
    end

    def prerequisites
      PrerequisiteTree.new(@course.prerequisites).map_courses { |node| enrich(node) }
    end

    def corequisites      = @course.corequisites.map { |ref| enrich(ref.merge("type" => "course")) }
    def mutual_exclusions = @course.mutual_exclusions.map { |ref| enrich(ref.merge("type" => "course")) }

    private

    def enrich(node)
      known = known_courses[CourseCode.key_of(node)]
      node.merge(
        "code"   => CourseCode.format(node["subject_code"], node["course_number"]),
        "title"  => known&.title,
        "linked" => known.present?
      )
    end

    def known_courses
      @known_courses ||= begin
        refs = PrerequisiteTree.new(@course.prerequisites).courses + @course.corequisites + @course.mutual_exclusions
        CatalogCourse.by_codes(refs.map { |ref| CourseCode.key_of(ref) })
                     .index_by(&:key)
      end
    end
  end
end
