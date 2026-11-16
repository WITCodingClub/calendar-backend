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

    private

    def rmp = Fields.rmp(@faculty)
  end
end
