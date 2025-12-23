# frozen_string_literal: true

# One-time task to backfill historical terms from Spring 2014 to present
# Run with: bundle exec rake one_time:backfill_historical_terms
#
# This task creates Term records for all semesters from Spring 2014 through
# the current academic period. It does NOT import course catalogs - use the
# admin UI or CatalogImportJob for that.
#
# Term UID encoding:
#   - Spring YYYY = YYYY20
#   - Summer YYYY = YYYY30
#   - Fall YYYY = (YYYY+1)10 (uses next year in UID)
#
# Examples:
#   - Spring 2014 = 201420
#   - Summer 2014 = 201430
#   - Fall 2014 = 201510 (uses 2015 in UID)

namespace :one_time do
  desc "Backfill historical terms from Fall 2012 to present"
  task backfill_historical_terms: :environment do
    START_YEAR = 2012
    END_YEAR = Time.current.year + 1 # Include upcoming year for future terms

    created_count = 0
    skipped_count = 0

    puts "Backfilling terms from Spring #{START_YEAR} to present..."
    puts "-" * 50

    (START_YEAR..END_YEAR).each do |year|
      # Process in chronological order: Spring, Summer, Fall
      [
        { season: :spring, uid: "#{year}20".to_i },
        { season: :summer, uid: "#{year}30".to_i },
        { season: :fall, uid: "#{year + 1}10".to_i }
      ].each do |term_data|
        # Skip future terms beyond Spring of next year
        next if term_data[:uid] > current_term_uid

        if Term.exists?(uid: term_data[:uid])
          puts "  SKIP: #{term_data[:season].to_s.capitalize} #{year} (#{term_data[:uid]}) - already exists"
          skipped_count += 1
        else
          term = Term.create!(
            uid: term_data[:uid],
            year: year,
            season: term_data[:season]
          )
          puts "  CREATE: #{term.name} (#{term.uid})"
          created_count += 1
        end
      end
    end

    puts "-" * 50
    puts "Done! Created #{created_count} terms, skipped #{skipped_count} existing terms."
    puts ""
    puts "Next steps:"
    puts "  1. Visit /admin/course_catalog to see all terms"
    puts "  2. Click 'Import' to fetch course catalogs for each term"
    puts "  3. Note: Historical imports may take time and some terms may not have data"
  end

  def current_term_uid
    today = Time.current
    year = today.year

    # Determine current season based on month
    case today.month
    when 1..5  # Spring semester
      "#{year}20".to_i
    when 6..7  # Summer semester
      "#{year}30".to_i
    when 8..12 # Fall semester
      "#{year + 1}10".to_i
    end
  end
end
