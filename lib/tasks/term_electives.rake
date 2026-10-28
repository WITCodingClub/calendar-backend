# frozen_string_literal: true

namespace :term_electives do
  # The job holds a lock, so a run from here does not overlap the nightly run.
  desc "Queue the import of the elective list PDFs on the Registrar's page"
  task import: :environment do
    TermElectives::ImportJob.perform_later
    puts "Queued the import of the term elective lists."
  end
end
