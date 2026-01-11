# frozen_string_literal: true

namespace :courses do
  desc "Refresh course titles from LeopardWeb (fetches raw titles and re-applies titleize_with_roman_numerals)"
  task :refresh_titles, [:term_uid] => :environment do |_t, args|
    include ApplicationHelper

    term_uid = args[:term_uid]

    if term_uid.blank?
      # Default to current and next term
      current_term = Term.current
      next_term = Term.next
      term_uids = [current_term&.uid, next_term&.uid].compact
      puts "No term specified, using current (#{current_term&.uid}) and next (#{next_term&.uid}) terms"
    else
      term_uids = [term_uid]
    end

    if term_uids.empty?
      puts "No terms found to refresh"
      exit 1
    end

    total_updated = 0
    total_failed = 0

    term_uids.each do |uid|
      puts "\n#{'=' * 50}"
      puts "Fetching courses for term #{uid} from LeopardWeb..."

      result = LeopardWebService.get_course_catalog(term: uid)

      unless result[:success]
        puts "Failed to fetch courses: #{result[:error]}"
        next
      end

      courses = result[:courses]
      puts "Fetched #{courses.count} courses from LeopardWeb"

      updated = 0
      failed = 0
      skipped = 0

      courses.each do |course_data|
        crn = course_data["courseReferenceNumber"]
        raw_title = course_data["courseTitle"]

        next if raw_title.blank?

        # Find existing course
        course = Course.find_by(crn: crn, term: Term.find_by(uid: uid))
        unless course
          skipped += 1
          next
        end

        # Apply the corrected titleize function to the RAW title from LeopardWeb
        new_title = titleize_with_roman_numerals(raw_title)

        # Only update if different
        if course.title != new_title
          begin
            course.update!(title: new_title)
            updated += 1
            puts "✓ CRN #{crn}: '#{course.title_was}' -> '#{new_title}'"
          rescue => e
            failed += 1
            puts "✗ CRN #{crn}: #{e.message}"
          end
        end
      end

      puts "\nTerm #{uid}: Updated #{updated}, Failed #{failed}, Skipped #{skipped}"
      total_updated += updated
      total_failed += failed
    end

    puts "\n#{'=' * 50}"
    puts "TOTAL: Updated #{total_updated}, Failed #{total_failed}"
  end
end
