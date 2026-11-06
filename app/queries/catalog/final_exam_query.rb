# frozen_string_literal: true

module Catalog
  # Finds the final exams of one term, in date and time order. The dashboard
  # finals page uses this object.
  #
  # q: a course code ("COMP 2350") matches that course, a five-digit number
  # matches a CRN, and other words match the course title or subject, each
  # word on its own.
  class FinalExamQuery
    def initialize(scope = FinalExam.all)
      @scope = scope
    end

    # @return [ActiveRecord::Relation<FinalExam>]
    def call(term:, q: nil, course_ids: nil)
      relation = @scope.where(term: term).includes(course: :faculties).order(:exam_date, :start_time, :crn)
      relation = relation.where(course_id: course_ids) unless course_ids.nil?
      q.present? ? search(relation, q.to_s.strip) : relation
    end

    private

    def search(relation, query)
      relation = relation.left_joins(:course)
      subject_code, course_number = CatalogCourse.parse_code(query)
      if subject_code
        # Course#prefix: the subject is "Computer Science (COMP)" or "COMP".
        return relation.where(courses: { course_number: course_number })
                       .where("courses.subject ILIKE :code OR courses.subject ILIKE :wrapped",
                              code: subject_code, wrapped: "%(#{subject_code})")
      end

      query.split.reduce(relation) do |scope, word|
        next scope.where(crn: word.to_i) if word.match?(/\A\d{5}\z/)

        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(word)}%"
        scope.where("courses.title ILIKE :q OR courses.subject ILIKE :q", q: pattern)
      end
    end
  end
end
