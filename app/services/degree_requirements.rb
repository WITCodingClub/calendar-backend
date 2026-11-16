# frozen_string_literal: true

# Imports the degree requirements of each catalog year from the academic
# catalog at catalog.wit.edu (CourseLeaf). docs/degree-requirements.md
# describes the sources and the tables.
module DegreeRequirements
  class Error < StandardError; end

  # A response that is not a success and not a 404. The job retries it.
  class FetchError < Error; end

  # The program list is much shorter than the last import of the same year.
  # The site changed or a page was cut short, so the import keeps the old data.
  class ImportShrankError < Error; end

  SITE_URL = "https://catalog.wit.edu"

  # The Double Leopard (4+1 master's) page. The catalog does not list these
  # programs, so PathwaySync reads them here.
  DOUBLE_LEOPARD_URL = "https://wit.edu/admissions/graduate/accelerated-masters-degrees"

  # 2025-2026 has no archive on the catalog site. The Wayback Machine has its
  # pages; this is the capture time to ask for. Each page still has to name
  # the right catalog year (CatalogPage#start_year).
  WAYBACK_TIMESTAMPS = { 2025 => "20260301000000" }.freeze

  # A path of the catalog site in the Wayback capture of a catalog year. raw
  # gives the page as it was saved, for the import. Without it, the URL opens
  # the capture page for a person.
  def self.wayback_url(start_year, path, raw: false)
    "https://web.archive.org/web/#{WAYBACK_TIMESTAMPS.fetch(start_year)}#{'id_' if raw}/#{SITE_URL}#{path}"
  end

  # The program page a requirement set came from, or nil. A set from the
  # Wayback Machine links to the capture, because the catalog site has no
  # copy of that year.
  def self.page_url(set)
    return nil if set.path.blank?

    start_year = set.catalog_year.start_year
    set.source_wayback? && WAYBACK_TIMESTAMPS.key?(start_year) ? wayback_url(start_year, set.path) : "#{SITE_URL}#{set.path}"
  end
end
