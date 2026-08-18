# frozen_string_literal: true

module Catalog
  # Faculty as the public catalog API returns them.
  #
  # Email, phone, and office location are deliberately omitted: the API is
  # unauthenticated, and a scrapeable staff contact list is not something this
  # feed should publish.
  class InstructorSerializer
    def initialize(faculty)
      @faculty = faculty
    end

    def as_json(*)
      return nil if @faculty.nil?

      {
        pub_id:     @faculty.public_id,
        name:       @faculty.full_name,
        first_name: @faculty.first_name,
        last_name:  @faculty.last_name,
        title:      @faculty.title,
        department: @faculty.department,
        school:     @faculty.school,
        rmp:        rmp
      }
    end

    # Rate My Professors reports "no data" as sentinel numbers: 0 for an average
    # with no ratings behind it, -1 for an unknown would-take-again percentage.
    # Those must not leave as if they were real scores.
    #
    # Shared with Types::InstructorType so both API surfaces agree.
    def self.rmp_for(faculty)
      stats = faculty.rmp_stats
      return nil if stats.nil?
      return nil if stats[:num_ratings].to_i.zero?

      would_take_again = stats[:would_take_again_percent]

      {
        id:                       faculty.rmp_id,
        avg_rating:               stats[:avg_rating],
        avg_difficulty:           stats[:avg_difficulty],
        num_ratings:              stats[:num_ratings],
        would_take_again_percent: (would_take_again if would_take_again.to_f >= 0)
      }
    end

    private

    def rmp
      self.class.rmp_for(@faculty)
    end
  end
end
