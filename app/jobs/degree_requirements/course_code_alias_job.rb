# frozen_string_literal: true

module DegreeRequirements
  # Downloads the 2014-2015 and 2015-2016 PDF catalogs and finds the course
  # code aliases of the renumbering (DegreeRequirements::CourseCodeAliasFinder).
  # `bin/rails degree_requirements:course_code_aliases` runs it.
  class CourseCodeAliasJob < ApplicationJob
    queue_as :low

    retry_on FetchError, wait: :polynomially_longer, attempts: 3

    def perform
      client = CatalogSiteClient.new
      texts = [ CourseCodeAliasFinder::OLD_YEAR, CourseCodeAliasFinder::NEW_YEAR ].index_with do |start_year|
        url = PdfCatalog.url_for(start_year)
        pdf = client.get(url, binary: true)
        raise FetchError, "GET #{url}: not found" if pdf.nil?

        FinalsSchedules::PdfText.extract(pdf).scrub.delete("\0")
      end
      CourseCodeAliasFinder.new(texts: texts).call
    end
  end
end
