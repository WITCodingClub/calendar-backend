# frozen_string_literal: true

module AcademicProfiles
  # Which course codes name the same course for degree planning. A course key
  # is a [subject_code, course_number] pair, such as ["COMP", 1000]. A key
  # matches itself and its old or new codes through a CourseCodeAlias that a
  # person checked, both ways. An unchecked alias does not count: the finder
  # can pair two courses that only share a title (#865).
  #
  # Every degree planning service of a request reads the same object
  # (CourseKeys.current), so the aliases load once.
  class CourseKeys
    def self.current
      Current.course_keys ||= new(CourseCodeAlias.reviewed_pairs)
    end

    # aliases: each key with the keys of its old and new codes
    # (CourseCodeAlias.reviewed_pairs).
    def initialize(aliases)
      @aliases = aliases
    end

    def equivalents(key) = [ key, *@aliases.fetch(key, []) ]

    def expand(keys) = keys.flat_map { |key| equivalents(key) }.uniq

    def same?(key, other) = equivalents(key).include?(other)

    # A code and its old or new codes, as "SUBJ 1234". A code that does not
    # parse stays as it is.
    def equivalent_codes(code)
      key = CourseCode.parse(code)
      key ? equivalents(key).map { |found| CourseCode.format(*found) }.uniq : [ code ]
    end
  end
end
