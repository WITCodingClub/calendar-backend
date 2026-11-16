# frozen_string_literal: true

namespace :terms do
  desc "Update term dates from valid course data"
  task update_from_courses: :environment do
    puts "Updating term dates from valid course data..."

    Term.find_each do |term|
      old_start = term.start_date
      old_end   = term.end_date

      term.update_dates_from_courses!
      term.reload

      if term.start_date != old_start || term.end_date != old_end
        puts "  #{term.name}: #{old_start} to #{old_end} -> #{term.start_date} to #{term.end_date}"
      end
    end

    puts "Done!"
  end

  # A term date outside the term's window (Term#date_window) is cleared, then
  # filled again from the term's courses and the university calendar, with the
  # same rules as UniversityCalendar::SyncJob. A date with no source stays
  # empty until the next sync finds one.
  desc "Clear term dates outside the term's window and detect them again"
  task fix_implausible_dates: :environment do
    Term.find_each do |term|
      fields = term.implausible_date_fields
      next if fields.empty?

      old_dates = "#{term.start_date} to #{term.end_date}"
      term.update!(fields.index_with(nil))
      term.update_dates_from_courses! if term.courses.exists?

      detected = UniversityCalendarEvent.detect_term_dates(term.year, term.season)
      fill = { start_date: detected[:start_date], end_date: detected[:end_date] }.select { |field, value| value && term[field].nil? }
      term.update!(fill) if fill.any?

      puts "  #{term.name}: #{old_dates} -> #{term.start_date} to #{term.end_date}"
    end

    puts "Done!"
  end
end
