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

    # "COMP 1000", "COMP1000", or "comp-1000" as ["COMP", 1000], or nil.
    def self.parse(code) = CatalogCourse.parse_code(code)

    # ["COMP", 1000] as "COMP 1000", the form of every code in a response.
    def self.format(key) = "#{key.first} #{key.last}"

    # aliases: each key with the keys of its old and new codes.
    def initialize(aliases = {})
      @aliases = aliases
    end

    # A key and the keys of its old and new codes.
    def equivalents(key) = [ key, *@aliases.fetch(key, []) ]

    # Every key of keys with its old and new codes, each one time.
    def expand(keys) = keys.flat_map { |key| equivalents(key) }.uniq

    def same?(key, other) = equivalents(key).include?(other)

    # A code and its old or new codes, as "SUBJ 1234". A code that does not
    # parse stays as it is.
    def equivalent_codes(code)
      key = self.class.parse(code)
      key ? equivalents(key).map { |found| self.class.format(found) }.uniq : [ code ]
    end
  end
end
