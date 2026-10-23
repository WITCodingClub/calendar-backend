# frozen_string_literal: true

namespace :degree_requirements do
  # The first catalog year the catalog site has as HTML. Older years are PDFs (#865).
  first_html_year = 2019

  desc "Queue the import of one catalog year: bin/rails 'degree_requirements:import[2024]'. " \
       "FORCE=1 imports an index that lists far fewer programs than the last import."
  task :import, [ :start_year ] => :environment do |_, args|
    start_year = Integer(args[:start_year], exception: false)
    abort "Give the first year of the catalog year, for example degree_requirements:import[2024]" if start_year.nil?

    force = ENV["FORCE"].present?
    DegreeRequirements::ImportJob.perform_later(start_year, force: force)
    puts "Queued the import of #{start_year}-#{start_year + 1}#{' with force' if force}."
  end

  desc "Queue the import of every catalog year from #{first_html_year}-#{first_html_year + 1} to this year"
  task import_all: :environment do
    (first_html_year..Date.current.year).each do |start_year|
      DegreeRequirements::ImportJob.perform_later(start_year)
    end
    puts "Queued #{first_html_year}..#{Date.current.year}. A year that is not published yet is marked missing."
  end
end
