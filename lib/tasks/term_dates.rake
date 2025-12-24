# frozen_string_literal: true

namespace :terms do
  desc "Reset all term dates to reasonable defaults based on year/season"
  task reset_dates: :environment do
    puts "Resetting term dates to defaults..."

    Term.find_each do |term|
      dates = case term.season.to_sym
              when :spring
                { start_date: Date.new(term.year, 1, 6), end_date: Date.new(term.year, 4, 20) }
              when :summer
                { start_date: Date.new(term.year, 5, 4), end_date: Date.new(term.year, 8, 15) }
              when :fall
                { start_date: Date.new(term.year, 8, 25), end_date: Date.new(term.year, 12, 15) }
              end

      term.update!(dates)
      puts "  #{term.name}: #{dates[:start_date]} to #{dates[:end_date]}"
    end

    puts "Done! Reset #{Term.count} terms."
  end

  desc "Update term dates from valid course data"
  task update_from_courses: :environment do
    puts "Updating term dates from valid course data..."

    Term.find_each do |term|
      old_start = term.start_date
      old_end = term.end_date

      term.update_dates_from_courses!
      term.reload

      if term.start_date != old_start || term.end_date != old_end
        puts "  #{term.name}: #{old_start} to #{old_end} -> #{term.start_date} to #{term.end_date}"
      end
    end

    puts "Done!"
  end

  desc "Fix course dates to match their term (for courses with bad dates)"
  task fix_course_dates: :environment do
    puts "Fixing course dates to match term dates..."

    fixed = 0
    Course.includes(:term).find_each do |course|
      next if course.term.nil?

      term = course.term
      start_valid = course.start_date&.year&.between?(term.year - 1, term.year)
      end_valid = course.end_date&.year&.between?(term.year, term.year + 1)

      unless start_valid && end_valid
        course.update_columns(start_date: term.start_date, end_date: term.end_date)
        fixed += 1
      end
    end

    puts "Done! Fixed #{fixed} courses with invalid dates."
  end

  desc "Full date reset: reset terms, fix courses, then refine from valid courses"
  task full_reset: :environment do
    puts "=== Full Date Reset ==="
    puts ""

    Rake::Task["terms:reset_dates"].invoke
    puts ""

    Rake::Task["terms:fix_course_dates"].invoke
    puts ""

    Rake::Task["terms:update_from_courses"].invoke
    puts ""

    puts "=== Complete ==="
  end
end
