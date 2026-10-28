# frozen_string_literal: true

# Imports the elective lists that each school publishes for a term. The
# Registrar's "Technical, Major, and HSS Electives" page links one PDF for
# each school. docs/term-electives.md describes the import.
module TermElectives
  class Error < StandardError; end

  # A response that is not a success and not a 404. The job retries it.
  class FetchError < Error; end

  PAGE_URL = "https://wit.edu/academics/registrar/how-to/technical-major-and-huss-electives"
  USER_AGENT = "WITCalendarBot/1.0"

  # The school of a list, from a word in the file name, such as
  # "SCDS_Electives_Spring 2027.pdf".
  SCHOOLS = %w[SCDS HSS SOM ARCH SOE SOS].freeze
end
