# frozen_string_literal: true

module AcademicProfiles
  # Which courses an elective list takes: a course on the list (or an old or
  # new code of one), a course in one of its subjects, or, for a list of any
  # course, any course for degree credit. DegreeProgress fills the elective
  # slots with it, ElectiveCandidates (#993) finds the courses of a term that
  # fill a slot, and MinorFit (#998) finds the slots that a course of a minor
  # can fill.
  class ElectiveListRule
    CO_OP_SUBJECT = "COOP"

    # group: an ElectiveGroup with its courses loaded.
    def initialize(group, course_keys)
      @group = group
      @keys = course_keys.expand(group.courses.map { |course| [ course.subject_code, course.course_number ] }).to_set
    end

    # Any course means a course for degree credit: not a co-op and not a
    # course below 1000, such as ENGL0700.
    def self.degree_credit?(key)
      key.first != CO_OP_SUBJECT && key.last.to_i >= 1000
    end

    # true when the list takes the course with this [subject, number] key.
    def accepts?(key)
      (any_course? && self.class.degree_credit?(key)) || @keys.include?(key) ||
        @group.subject_codes.include?(key.first)
    end

    # true when the list takes some course of this subject: a list of any
    # course, or a list with the subject. A list of named courses gives false.
    def accepts_subject?(subject)
      (any_course? && subject != CO_OP_SUBJECT) || @group.subject_codes.include?(subject)
    end

    # true when the list names a course of this subject, such as PSYC 3100
    # for PSYC.
    def names_subject?(subject)
      @keys.any? { |key| key.first == subject }
    end

    def any_course? = @group.any_course

    # true for a list that names courses or subjects, not any course.
    def names_courses? = @keys.any? || @group.subject_codes.any?

    def name = @group.name
  end
end
