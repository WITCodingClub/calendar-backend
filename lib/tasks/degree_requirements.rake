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

  desc "Queue the import of one PDF catalog year, 2013 to 2018: bin/rails 'degree_requirements:import_pdf[2014]'. " \
       "Each set it writes waits in /admin/requirement_set_reviews."
  task :import_pdf, [ :start_year ] => :environment do |_, args|
    start_year = Integer(args[:start_year], exception: false)
    years = DegreeRequirements::PdfCatalog::FILES.keys
    abort "Give the first year of a PDF catalog year: #{years.join(', ')}" unless years.include?(start_year)

    DegreeRequirements::PdfImportJob.perform_later(start_year)
    puts "Queued the PDF import of #{start_year}-#{start_year + 1}."
  end

  desc "Queue the import of every PDF catalog year, 2013-2014 to 2018-2019"
  task import_pdf_all: :environment do
    DegreeRequirements::PdfCatalog::FILES.each_key { |start_year| DegreeRequirements::PdfImportJob.perform_later(start_year) }
    puts "Queued #{DegreeRequirements::PdfCatalog::FILES.keys.minmax.join('..')}."
  end

  desc "Find course code aliases for the renumbering in 2015-2016 (COMP128 to COMP1000). " \
       "Each new alias waits in /admin/course_code_alias_reviews."
  task course_code_aliases: :environment do
    result = DegreeRequirements::CourseCodeAliasJob.perform_now
    puts "#{result.created} new aliases (#{result.catalog} from the catalogs, #{result.banner} from Banner), " \
         "#{result.existing} already stored, #{result.conflicts} left out because the sources disagree."
  end

  desc "Queue the import of every catalog year from #{first_html_year}-#{first_html_year + 1} to this year"
  task import_all: :environment do
    (first_html_year..Date.current.year).each do |start_year|
      DegreeRequirements::ImportJob.perform_later(start_year)
    end
    puts "Queued #{first_html_year}..#{Date.current.year}. A year that is not published yet is marked missing."
  end
end
