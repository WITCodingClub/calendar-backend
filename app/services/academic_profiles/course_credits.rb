# frozen_string_literal: true

module AcademicProfiles
  # The one credit rule of degree planning. A course has the credit hours of
  # its sections, else of its CatalogCourse row: Banner leaves the credit
  # hours of some sections empty, and CatalogCourse does not know every old
  # code. When neither knows them:
  #
  # - a course the student took counts 0, so earned credits are never a
  #   guess;
  # - a course still to take, or an open slot, counts DEFAULT in an estimate.
  class CourseCredits
    # Most WIT courses have 4 credits.
    DEFAULT = 4

    # The credit hours that Banner or the catalog knows, or nil.
    def self.known(section_hours, catalog_hours) = section_hours || catalog_hours

    # The credits of a course still to take, for an estimate.
    def self.estimate(hours) = hours || DEFAULT

    # course_details: the CourseDetails of the response.
    def initialize(course_details)
      @details = course_details
    end

    # A course the student took (CourseHistory::Taken).
    def of(course) = self.class.known(course.credits, @details.for(course.key)[:credit_hours]) || 0

    # A course nobody took, by its [subject, number] key, for an estimate.
    def of_key(key) = self.class.estimate(@details.for(key)[:credit_hours])

    def sum(courses) = courses.sum { |course| of(course) }
  end
end
