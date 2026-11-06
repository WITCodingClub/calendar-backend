# frozen_string_literal: true

namespace :courses do
  desc "Get course titles from LeopardWeb again (a term_uid, ALL=1 for every term with courses, or else the current and next terms)"
  task :refresh_titles, [ :term_uid ] => :environment do |_t, args|
    terms = if args[:term_uid].present?
              Term.where(uid: args[:term_uid]).to_a
    elsif ENV["ALL"] == "1"
              Term.where(id: Course.select(:term_id)).reverse_chronological.to_a
    else
              [ Term.current, Term.next ].compact
    end

    if terms.empty?
      puts "No terms found to refresh"
      exit 1
    end

    puts "Refreshing #{terms.size} terms: #{terms.map(&:uid).join(", ")}"
    total_updated = 0
    total_failed  = 0

    terms.each do |term|
      puts "\n#{"=" * 50}"
      puts "Fetching courses for term #{term.uid} from LeopardWeb..."

      result = Catalog::LeopardWebClient.get_course_catalog(term: term.uid)

      unless result[:success]
        puts "Failed to fetch courses: #{result[:error]}"
        next
      end

      puts "Fetched #{result[:courses].count} courses from LeopardWeb"
      courses_by_crn = term.courses.index_by(&:crn)
      updated = 0
      failed  = 0
      skipped = 0

      # One EXISTS query for each changed course, not one for each save.
      CourseChangeTrackable.with_enrollment_cache do
        result[:courses].each do |course_data|
          raw_title = course_data["courseTitle"]
          next if raw_title.blank?

          course = courses_by_crn[course_data["courseReferenceNumber"].to_i]
          unless course
            skipped += 1
            next
          end

          new_title = Course.normalize_value_for(:title, raw_title)
          next if course.title == new_title

          old_title = course.title
          begin
            # update! runs the callbacks, so enrolled users get a calendar sync.
            course.update!(title: new_title)
            updated += 1
            puts "CRN #{course.crn}: '#{old_title}' -> '#{new_title}'"
          rescue ActiveRecord::ActiveRecordError => e
            Rails.error.report(e, handled: true, context: { course_id: course.id })
            failed += 1
            puts "CRN #{course.crn}: #{e.message}"
          end
        end
      end

      puts "Term #{term.uid}: Updated #{updated}, Failed #{failed}, Skipped #{skipped}"
      total_updated += updated
      total_failed  += failed
    end

    puts "\n#{"=" * 50}"
    puts "TOTAL: Updated #{total_updated}, Failed #{total_failed}"
  end
end

namespace :courses do
  desc "Run Courses::TitleFormatter on stored course titles of the current and future terms (ALL=1 for every term; no LeopardWeb request)"
  task normalize_titles: :environment do
    courses = Course.where.not(title: nil)
    courses = courses.where(term: Term.current_and_future) unless ENV["ALL"] == "1"
    updated = 0

    # One EXISTS query for each changed course, not one for each save.
    CourseChangeTrackable.with_enrollment_cache do
      courses.find_each do |course|
        new_title = Course.normalize_value_for(:title, course.title)
        next if new_title == course.title

        old_title = course.title
        # update! runs the callbacks, so enrolled users get a calendar sync.
        course.update!(title: new_title)
        updated += 1
        puts "CRN #{course.crn}: '#{old_title}' -> '#{new_title}'"
      end
    end

    puts "Updated #{updated} course titles"
  end
end
