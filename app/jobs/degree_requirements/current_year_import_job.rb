# frozen_string_literal: true

module DegreeRequirements
  # Finds the catalog year that catalog.wit.edu shows now and imports it.
  # It runs each month (config/recurring.yml): a new catalog comes out in
  # the summer, and the current one can change during the year. Pages that
  # did not change are skipped.
  class CurrentYearImportJob < ApplicationJob
    queue_as :low

    def perform
      html = CatalogSiteClient.new.get("#{SITE_URL}/programs-az/")
      start_year = CatalogSource.page_start_year(html)
      raise Error, "the catalog site names no catalog year" if start_year.nil?

      ImportJob.perform_later(start_year)
      start_year
    end
  end
end
