# frozen_string_literal: true

namespace :courses do
  desc "Re-sync section instructors from Banner (fixes sections that changed hands)"
  task :refresh_faculty, [ :term_uid ] => :environment do |_t, args|
    term_uid = args[:term_uid]

    if term_uid.blank?
      term_uids = (Term.active.pluck(:uid) + Term.current_and_future.pluck(:uid)).uniq
      puts "No term specified, using active, current and future terms: #{term_uids.join(', ')}"
    else
      term_uids = [ term_uid ]
    end

    if term_uids.empty?
      puts "No terms found to refresh"
      exit 1
    end

    total_changed = 0
    total_failed  = 0

    term_uids.each do |uid|
      term = Term.find_by(uid: uid)
      unless term
        puts "Term #{uid} not found, skipping"
        next
      end

      puts "\n#{'=' * 50}"
      puts "Refreshing instructors for #{term.name} (#{uid})"

      changed = 0
      failed  = 0

      CourseChangeTrackable.with_enrollment_cache do
        term.courses.find_each(batch_size: 50) do |course|
          details = LeopardWebService.get_class_details(term: uid, course_reference_number: course.crn)

          if details.nil? || details[:faculty].blank?
            puts "  CRN #{course.crn}: Banner reported no instructor, leaving as is"
            next
          end

          before = course.faculties.map(&:full_name)

          if FacultyIngestService.call(course: course, raw_faculty: details[:faculty])
            changed += 1
            puts "  CRN #{course.crn}: #{before.join(', ').presence || 'none'} -> #{course.faculties.map(&:full_name).join(', ')}"
          end

          # Banner rate limits, and this walks every section in the term.
          sleep 0.1
        rescue => e
          failed += 1
          puts "  CRN #{course.crn}: failed (#{e.message})"
        end
      end

      puts "Term #{uid}: #{changed} changed, #{failed} failed"
      total_changed += changed
      total_failed  += failed
    end

    puts "\n#{'=' * 50}"
    puts "Done: #{total_changed} sections corrected, #{total_failed} failed"
  end
end
