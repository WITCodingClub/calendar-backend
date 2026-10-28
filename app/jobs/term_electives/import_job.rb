# frozen_string_literal: true

module TermElectives
  # Imports the elective lists on the Registrar's page (TermElectives::Importer).
  # It runs each night (config/recurring.yml): the schools send new lists
  # during registration, and the page gets a new version of a file without
  # notice. `bin/rails term_electives:import` queues it now.
  class ImportJob < ApplicationJob
    CONCURRENCY_GROUP = "TermElectivesImportJob"

    queue_as :low

    # Two runs at once would write the same lists. A run is a few PDFs, plus
    # the retries of a slow site.
    limits_concurrency to: 1, group: CONCURRENCY_GROUP, key: ->(*) { "term_electives_import" }, duration: 30.minutes

    retry_on FetchError, wait: :polynomially_longer, attempts: 3

    def perform
      Importer.new.call
    end
  end
end
