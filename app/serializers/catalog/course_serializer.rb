# frozen_string_literal: true

module Catalog
  # One course (CatalogCourse) as the public catalog API returns it, with the
  # description, prerequisites, corequisites, restrictions, mutual exclusions,
  # catalog entry, fees, learning objectives, and the courses it unlocks
  # (CourseRequisites gives the courses their titles). summary is the short
  # form of a list.
  #
  # Pass a term to add that term's sections.
  class CourseSerializer
    def self.summary(course)
      {
        code:              course.code,
        subject_code:      course.subject_code,
        course_number:     course.course_number,
        title:             course.title,
        credit_hours:      course.credit_hours,
        typically_offered: course.typically_offered
      }
    end

    def initialize(catalog_course, term: nil)
      @course = catalog_course
      @term   = term
    end

    def as_json(*)
      return nil if @course.nil?

      requisites = CourseRequisites.new(@course)
      self.class.summary(@course).merge(
        description:         @course.description,
        prerequisites:       requisites.prerequisites,
        corequisites:        requisites.corequisites,
        restrictions:        @course.restrictions,
        mutual_exclusions:   requisites.mutual_exclusions,
        college:             @course.college,
        division:            @course.division,
        department:          @course.department,
        levels:              @course.levels,
        grading_modes:       @course.grading_modes,
        fees:                @course.fees,
        learning_objectives: @course.learning_objectives,
        unlocks:             @course.unlocks.order(:subject_code, :course_number).distinct.map { |c| self.class.summary(c) },
        details_term_uid:    @course.source_term&.uid,
        details_fetched_at:  @course.details_fetched_at
      ).tap { |full| full[:sections] = sections if @term }
    end

    private

    def sections
      relation = SectionQuery.with_associations(
        SectionQuery.new.call(term_uid: @term.uid, subject: [ @course.subject_code ], course_number: [ @course.course_number ])
      )
      relation.map { |section| SectionSerializer.new(section, catalog_courses: {}).as_json.except(:course) }
    end
  end
end
