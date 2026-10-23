# frozen_string_literal: true

module DegreeRequirements
  # Imports the programs of one catalog year (DegreeRequirements::Importer),
  # then queues the course import. `bin/rails degree_requirements:import`
  # queues it, and CurrentYearImportJob queues it each month.
  class ImportJob < ApplicationJob
    CONCURRENCY_GROUP = "DegreeRequirementsImportJob"

    queue_as :low

    # One import of a year at a time. A year is about 130 pages, half a
    # second apart, plus the retries of a slow site.
    limits_concurrency to: 1, group: CONCURRENCY_GROUP, key: ->(start_year) { "degree_requirements_import:#{start_year}" },
                       duration: 1.hour

    retry_on FetchError, wait: :polynomially_longer, attempts: 3

    def perform(start_year)
      catalog_year = CatalogYear.find_or_create_by!(start_year: start_year)
      result = Importer.new(catalog_year).call
      CourseImportJob.perform_later(start_year) if result.status == :imported
      result
    rescue StandardError
      catalog_year&.update_columns(status: "failed")
      raise
    end
  end
end
