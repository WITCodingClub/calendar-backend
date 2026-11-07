# frozen_string_literal: true

namespace :degree_requirements do
  # The first catalog year that matches Banner data (Spring 2014). Years
  # before 2019-2020 are PDFs (#865): DegreeRequirements::PdfCatalog::FILES.
  first_year = 2013

  desc "Queue the import of one catalog year: bin/rails 'degree_requirements:import[2024]'. " \
       "FORCE=1 imports an index that lists far fewer programs than the last import."
  task :import, [ :start_year ] => :environment do |_, args|
    start_year = Integer(args[:start_year], exception: false)
    abort "Give the first year of the catalog year, for example degree_requirements:import[2024]" if start_year.nil?

    force = ENV["FORCE"].present?
    DegreeRequirements::ImportJob.perform_later(start_year, force: force)
    puts "Queued the import of #{start_year}-#{start_year + 1}#{' with force' if force}."
  end

  desc "Link the elective slots of every stored plan to the shared lists: HSS, English sequence, co-op, " \
       "and free electives. Each import also does it."
  task shared_electives: :environment do
    linked = RequirementSet.find_each.sum { |set| DegreeRequirements::SharedElectives.call(set) }
    ElectiveGroupCourse.link_catalog_courses
    puts "Linked #{linked} elective slots."
  end

  desc "Sync the program pathways (Double Leopard, 5-year) from the catalog and wit.edu now. " \
       "Each import of the current catalog also runs it."
  task pathways: :environment do
    result = DegreeRequirements::PathwaySync.new.call
    puts "Saved #{result.saved.size} pathways, set #{result.deactivated} inactive."
    puts "Skipped (a program is not imported yet): #{result.skipped.join(', ')}" if result.skipped.any?
    puts "No master's program for these Double Leopard names: #{result.unmatched.join(', ')}" if result.unmatched.any?
  end

  desc "Queue the import of every catalog year from #{first_year}-#{first_year + 1} to this year"
  task import_all: :environment do
    (first_year..Date.current.year).each do |start_year|
      DegreeRequirements::ImportJob.perform_later(start_year)
    end
    puts "Queued #{first_year}..#{Date.current.year}. A year that is not published yet is marked missing."
  end

  desc "Move the stored catalog years of each renamed program (DegreeProgram::RENAMED_SLUGS) to its new slug. " \
       "Each import also does it."
  task merge_renamed: :environment do
    DegreeRequirements::ProgramMerge.renamed.each do |result|
      case result.status
      when :merged then puts "#{result.old_slug}: moved #{result.moved_sets} catalog years to #{result.new_slug}."
      when :renamed then puts "#{result.old_slug}: renamed to #{result.new_slug}."
      when :stopped then puts "#{result.old_slug}: stopped, #{result.error}."
      else puts "#{result.old_slug}: no program, nothing to do."
      end
    end
    AcademicProfiles::ProgramMatcher.relink_active
  end

  desc "Find course code aliases (COMP128 to COMP1000) from the catalogs and Banner, for review on the admin page"
  task aliases: :environment do
    result = DegreeRequirements::AliasFinder.call
    puts "Added #{result.added} aliases (#{result.title_match} from the catalogs, #{result.banner} from Banner). " \
         "Review them at /admin/catalog_reviews."
  end
end
