# frozen_string_literal: true

module DegreeRequirements
  # Downloads the PDF catalog of one year from the previous catalogs page,
  # reads its text with pdftotext, and imports its plans of study
  # (DegreeRequirements::PdfImporter). `bin/rails
  # 'degree_requirements:import_pdf[2014]'` queues it.
  class PdfImportJob < ApplicationJob
    # The lock of ImportJob: both write requirement sets and link the
    # student programs again.
    CONCURRENCY_GROUP = "DegreeRequirementsImportJob"

    queue_as :low

    limits_concurrency to: 1, group: CONCURRENCY_GROUP, key: ->(*) { "degree_requirements_import" }, duration: 1.hour

    retry_on FetchError, wait: :polynomially_longer, attempts: 3

    def perform(start_year)
      url = PdfCatalog.url_for(start_year)
      raise Error, "#{start_year}-#{start_year + 1} has no PDF catalog" if url.nil?

      pdf = CatalogSiteClient.new.get(url, binary: true)
      raise FetchError, "GET #{url}: not found" if pdf.nil?

      text = FinalsSchedules::PdfText.extract(pdf).scrub.delete("\0")
      PdfImporter.new(CatalogYear.find_or_create_by!(start_year: start_year), text: text).call
    end
  end
end
