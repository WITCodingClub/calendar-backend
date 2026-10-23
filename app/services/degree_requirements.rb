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
  USER_AGENT = "WITCalendarBot/1.0"

  # 2025-2026 has no archive on the catalog site. The Wayback Machine has its
  # pages; this is the capture time to ask for. Each page still has to name
  # the right catalog year (CatalogPage#start_year).
  WAYBACK_TIMESTAMPS = { 2025 => "20260301000000" }.freeze
end
