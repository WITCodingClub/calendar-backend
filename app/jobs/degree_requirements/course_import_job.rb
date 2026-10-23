# frozen_string_literal: true

module DegreeRequirements
  # Imports the courses of one catalog year from the course search
  # (DegreeRequirements::CourseImporter). ImportJob queues it.
  class CourseImportJob < ApplicationJob
    CONCURRENCY_GROUP = "DegreeRequirementsCourseImportJob"

    queue_as :low

    # About 1,000 requests a quarter of a second apart.
    limits_concurrency to: 1, group: CONCURRENCY_GROUP,
                       key: ->(start_year) { "degree_requirements_courses:#{start_year}" }, duration: 1.hour

    retry_on FetchError, wait: :polynomially_longer, attempts: 3

    def perform(start_year)
      catalog_year = CatalogYear.find_by(start_year: start_year)
      return if catalog_year.nil?

      CourseImporter.new(catalog_year).call
    end
  end
end
