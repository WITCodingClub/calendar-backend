# frozen_string_literal: true

module AcademicProfiles
  # The HSS rules of DegreeProgress (#991): the categories of a major, which
  # categories can be checked, which course meets a category, and what counts
  # for a category (the hint). DegreeProgress uses it to fill the HSS slots
  # and to build `hss`. Other services, such as NextTermCourses, can use it to
  # read the same categories with the same results.
  #
  # A category is a hash of RequirementSet#hss_requirement: { "name",
  # "subject_codes", "courses" }, with courses such as "PHIL4401".
  class HssMatcher
    CODE = /\A([A-Z]+)(\d+)\z/

    # The categories of the major, or the Humanities and Social Sciences
    # categories when the set has no HSS requirement.
    def self.categories(set)
      (set.hss_requirement.presence || DegreeRequirements::HssNoteParser.default)["categories"]
    end

    # A category with no subject and no course, such as "Writing intensive",
    # has no matcher.
    def self.checkable?(category)
      category["subject_codes"].any? || category["courses"].any?
    end

    # What counts for a category: its subject codes and its courses, as
    # "PHIL 4401". nil for a category that cannot be checked.
    def self.hint(category)
      return nil unless checkable?(category)

      { subject_codes: category["subject_codes"], courses: category["courses"].map { |code| spaced(code) } }
    end

    # "PHIL4401" as "PHIL 4401", the form of the other codes of the response.
    def self.spaced(code)
      subject, number = code.match(CODE)&.captures
      subject ? "#{subject} #{number}" : code
    end

    # true for the elective list of an HSS slot: HSS Electives, Humanities
    # Electives, Social Science Electives, or a directed HSS elective.
    def self.slot_list?(name)
      return false if name.nil?

      rules = DegreeRequirements::SharedElectives
      [ rules::HSS, rules::HUMANITIES_RULE, rules::SOCIAL_SCIENCES_RULE ].map(&:name).include?(name) ||
        name.start_with?("HSS Elective (")
    end

    # aliases: each course key ([subject, number]) with its old or new keys,
    # as DegreeProgress reads them from CourseCodeAlias.
    def initialize(aliases)
      @aliases = aliases
    end

    # true when the course meets the category: its subject is one of the
    # category, or it is one of the courses (or an alias of one).
    # english_humanities is the third English course, which counts as
    # Humanities. A course responds to subject_code and key.
    def in_category?(category, course, english_humanities: nil)
      return true if english_humanities && category["name"] == "Humanities" && course.equal?(english_humanities)
      return true if category["subject_codes"].include?(course.subject_code)

      category["courses"].any? do |code|
        subject, number = code.match(CODE)&.captures
        subject && equivalents([ subject, number.to_i ]).include?(course.key)
      end
    end

    # The name of the first category, in category order, that the course
    # meets, or nil.
    def category_of(categories, course, english_humanities: nil)
      categories.find { |category| in_category?(category, course, english_humanities: english_humanities) }&.dig("name")
    end

    private

    def equivalents(code) = [ code, *@aliases.fetch(code, []) ]
  end
end
