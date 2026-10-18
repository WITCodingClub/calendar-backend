# frozen_string_literal: true

module Catalog
  # One course (CatalogCourse) as the public catalog API returns it, with the
  # description, prerequisites, corequisites, restrictions, and the courses it
  # unlocks. Each course in the prerequisite tree gets its title and whether
  # WIT Calendar knows the course (linked).
  #
  # Pass a term to add that term's sections.
  class CourseSerializer
    def initialize(catalog_course, term: nil, summary: false)
      @course  = catalog_course
      @term    = term
      @summary = summary
    end

    def as_json(*)
      return nil if @course.nil?

      json = {
        code:              @course.code,
        subject_code:      @course.subject_code,
        course_number:     @course.course_number,
        title:             @course.title,
        credit_hours:      @course.credit_hours,
        typically_offered: @course.typically_offered
      }
      return json if @summary

      json.merge(
        description:        @course.description,
        prerequisites:      enrich(@course.prerequisites),
        corequisites:       @course.corequisites.map { |ref| enrich(ref.merge("type" => "course")) },
        restrictions:       @course.restrictions,
        unlocks:            @course.unlocks.order(:subject_code, :course_number).distinct.map { |c| summary(c) },
        details_term_uid:   @course.source_term&.uid,
        details_fetched_at: @course.details_fetched_at
      ).tap { |full| full[:sections] = sections if @term }
    end

    def self.summary(course)
      new(course, summary: true).as_json
    end

    private

    def summary(course) = self.class.summary(course)

    def enrich(node)
      return nil if node.nil?
      return node.merge("operands" => node["operands"].map { |operand| enrich(operand) }) if node["operands"]
      return node unless node["type"] == "course"

      known = known_courses[[ node["subject_code"], node["course_number"].to_i ]]
      node.merge(
        "code"   => "#{node['subject_code']} #{node['course_number']}",
        "title"  => known&.title,
        "linked" => known.present?
      )
    end

    # Every course the tree and the corequisites name, in one query.
    def known_courses
      @known_courses ||= begin
        refs = course_refs(@course.prerequisites) + @course.corequisites
        pairs = refs.map { |ref| [ ref["subject_code"], ref["course_number"].to_i ] }.uniq
        if pairs.empty?
          {}
        else
          conditions = pairs.map { "(subject_code = ? AND course_number = ?)" }.join(" OR ")
          CatalogCourse.where(conditions, *pairs.flatten).index_by { |c| [ c.subject_code, c.course_number ] }
        end
      end
    end

    def course_refs(node)
      return [] if node.nil?
      return [ node ] if node["type"] == "course"

      Array(node["operands"]).flat_map { |operand| course_refs(operand) }
    end

    def sections
      relation = SectionQuery.with_associations(@course.sections_in(@term))
      relation.map { |section| SectionSerializer.new(section, catalog_courses: {}).as_json.except(:course) }
    end
  end
end
