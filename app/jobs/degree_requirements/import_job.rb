# frozen_string_literal: true

module DegreeRequirements
  # Imports the programs of one catalog year (DegreeRequirements::Importer),
  # then queues the course import. `bin/rails degree_requirements:import`
  # queues it, and CurrentYearImportJob queues it each month.
  #
  # A year before 2019-2020 has only a PDF (PdfCatalog::Importer), and the
  # course search API does not have it. 2025-2026 reads the PDF after the
  # Wayback Machine, for the programs that the Wayback Machine does not have.
  class ImportJob < ApplicationJob
    CONCURRENCY_GROUP = "DegreeRequirementsImportJob"

    queue_as :low

    # One import at a time, for every year: two years write the same
    # DegreeProgram rows. A year is about 130 pages, half a second apart (5
    # seconds on the Wayback Machine), plus the retries of a slow site.
    limits_concurrency to: 1, group: CONCURRENCY_GROUP, key: ->(*) { "degree_requirements_import" }, duration: 1.hour

    retry_on FetchError, wait: :polynomially_longer, attempts: 3

    def perform(start_year, force: false)
      catalog_year = CatalogYear.find_or_create_by!(start_year: start_year)
      return PdfCatalog::Importer.new(catalog_year).call if PdfCatalog.pdf_only?(start_year)

      result = Importer.new(catalog_year, force: force).call
      if result.status == :imported
        PdfCatalog::Importer.new(catalog_year).call if PdfCatalog::FILES.key?(start_year)
        CourseImportJob.perform_later(start_year)
      end
      result
    rescue StandardError
      # A year with stored data keeps its status. The executor reports the
      # error, and the data from the last import is still good.
      catalog_year.update_columns(status: "failed") if catalog_year && !catalog_year.requirement_sets.exists?
      raise
    end
  end
end
