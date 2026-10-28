# frozen_string_literal: true

namespace :term_electives do
  desc "Import the elective list PDFs on the Registrar's page now"
  task import: :environment do
    result = TermElectives::Importer.new.call
    puts result.to_h.map { |key, count| "#{key}: #{count}" }.join(", ")
  end
end
