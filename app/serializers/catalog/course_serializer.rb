# frozen_string_literal: true

module Catalog
  # One course (CatalogCourse) as the public catalog API returns it, with the
  # description, prerequisites, corequisites, restrictions, mutual exclusions,
  # catalog entry, fees, learning objectives, and the courses it unlocks. Each
  # course in the prerequisite tree gets its title and whether WIT Calendar
  # knows the course (linked).
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
        description:         @course.description,
        prerequisites:       PrerequisiteTree.new(@course.prerequisites).map_courses { |node| enrich(node) },
        corequisites:        @course.corequisites.map { |ref| enrich(ref.merge("type" => "course")) },
        restrictions:        @course.restrictions,
        mutual_exclusions:   @course.mutual_exclusions.map { |ref| enrich(ref.merge("type" => "course")) },
        college:             @course.college,
        division:            @course.division,
        department:          @course.department,
        levels:              @course.levels,
        grading_modes:       @course.grading_modes,
        fees:                @course.fees,
        learning_objectives: @course.learning_objectives,
        unlocks:             @course.unlocks.order(:subject_code, :course_number).distinct.map { |c| summary(c) },
        details_term_uid:    @course.source_term&.uid,
        details_fetched_at:  @course.details_fetched_at
      ).tap { |full| full[:sections] = sections if @term }
    end

    def self.summary(course)
      new(course, summary: true).as_json
    end

    private

    def summary(course) = self.class.summary(course)

    # A course node with its title and whether WIT Calendar knows the course.
    def enrich(node)
      known = known_courses[[ node["subject_code"], node["course_number"].to_i ]]
      node.merge(
        "code"   => CourseCode.format(node["subject_code"], node["course_number"]),
        "title"  => known&.title,
        "linked" => known.present?
      )
    end

    # Every course the tree, the corequisites, and the mutual exclusions name,
    # in one query.
    def known_courses
      @known_courses ||= begin
        refs = PrerequisiteTree.new(@course.prerequisites).courses + @course.corequisites + @course.mutual_exclusions
        CatalogCourse.by_codes(refs.map { |ref| [ ref["subject_code"], ref["course_number"].to_i ] })
                     .index_by { |c| [ c.subject_code, c.course_number ] }
      end
    end

    def sections
      relation = SectionQuery.with_associations(
        SectionQuery.new.call(term_uid: @term.uid, subject: [ @course.subject_code ], course_number: [ @course.course_number ])
      )
      relation.map { |section| SectionSerializer.new(section, catalog_courses: {}).as_json.except(:course) }
    end
  end
end
