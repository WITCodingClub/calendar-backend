# frozen_string_literal: true

module TermElectives
  # Imports the elective lists on the Registrar's page (TermElectives::Importer).
  # It runs each night (config/recurring.yml): the schools send new lists
  # during registration, and the page gets a new version of a file without
  # notice. `bin/rails term_electives:import` runs the import now.
  class ImportJob < ApplicationJob
    queue_as :low

    retry_on FetchError, wait: :polynomially_longer, attempts: 3

    def perform
      Importer.new.call
    end
  end
end
