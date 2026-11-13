# frozen_string_literal: true

module AcademicProfiles
  # Which courses an elective list takes: a course on the list (or an old or
  # new code of one), a course in one of its subjects, or, for a list of any
  # course, any course for degree credit. DegreeProgress#take_for fills the
  # elective slots with it, and MinorFit (#998) uses it to find the slots that
  # a course of a minor can fill.
  class ElectiveListRule
    # group: an ElectiveGroup with its courses loaded. aliases: each course
    # key with its old or new keys (CourseCodeAlias.reviewed_pairs).
    def initialize(group, aliases)
      @group = group
      @keys = group.courses.flat_map do |course|
        key = [ course.subject_code, course.course_number ]
        [ key, *aliases.fetch(key, []) ]
      end.to_set
    end

    # Any course means a course for degree credit: not a co-op and not a
    # course below 1000, such as ENGL0700.
    def self.degree_credit?(key)
      key.first != "COOP" && key.last.to_i >= 1000
    end

    # true when the list takes the course with this key ([subject, number]).
    def accepts?(key)
      (any_course? && self.class.degree_credit?(key)) || @keys.include?(key) ||
        @group.subject_codes.include?(key.first)
    end

    # true when the list takes some course of this subject: a list of any
    # course, or a list with the subject. A list of named courses gives false.
    def accepts_subject?(subject)
      (any_course? && subject != "COOP") || @group.subject_codes.include?(subject)
    end

    # true when the list names a course of this subject, such as PSYC 3100
    # for PSYC.
    def names_subject?(subject)
      @keys.any? { |key| key.first == subject }
    end

    def any_course? = @group.any_course

    def name = @group.name
  end
end
