namespace :courses do
  desc "Fix course formatting: Roman numerals in titles and spacing in section numbers"
  task fix_formatting: :environment do
    include ApplicationHelper

    puts "Finding courses with formatting issues..."

    # Find courses where title or section_number would change when normalized
    courses_to_fix = Course.where.not(title: nil).select do |course|
      title_needs_fix = course.title != titleize_with_roman_numerals(course.title)
      section_needs_fix = course.section_number.present? &&
                          course.section_number != normalize_section_number(course.section_number)
      title_needs_fix || section_needs_fix
    end

    puts "Found #{courses_to_fix.count} courses with formatting issues"

    if courses_to_fix.count == 0
      puts "No courses need fixing!"
      next
    end

    puts "\nCourses that will be updated:"
    courses_to_fix.each do |course|
      changes = []

      old_title = course.title
      new_title = titleize_with_roman_numerals(old_title)
      changes << "title: '#{old_title}' -> '#{new_title}'" if old_title != new_title

      old_section = course.section_number
      new_section = normalize_section_number(old_section)
      changes << "section: '#{old_section}' -> '#{new_section}'" if old_section != new_section

      puts "CRN #{course.crn}: #{changes.join(', ')}"
    end

    print "\nProceed with updating #{courses_to_fix.count} courses? (y/N): "
    response = STDIN.gets.chomp.downcase

    unless response == 'y' || response == 'yes'
      puts "Cancelled."
      next
    end

    puts "\nUpdating courses..."
    updated_count = 0
    failed_count = 0
    affected_course_ids = []

    courses_to_fix.each do |course|
      begin
        updates = {}

        old_title = course.title
        new_title = titleize_with_roman_numerals(old_title)
        updates[:title] = new_title if old_title != new_title

        old_section = course.section_number
        new_section = normalize_section_number(old_section)
        updates[:section_number] = new_section if old_section != new_section

        if updates.any?
          course.update!(updates)
          updated_count += 1
          affected_course_ids << course.id
          puts "✓ CRN #{course.crn}: Updated #{updates.keys.join(', ')}"
        end
      rescue => e
        failed_count += 1
        puts "✗ CRN #{course.crn}: Failed - #{e.message}"
      end
    end

    puts "\n" + "=" * 50
    puts "COURSE UPDATE SUMMARY:"
    puts "Total courses processed: #{courses_to_fix.count}"
    puts "Successfully updated: #{updated_count}"
    puts "Failed: #{failed_count}"
    puts "=" * 50

    # Queue calendar syncs for affected users
    if updated_count > 0
      print "\nQueue calendar syncs for affected users? (y/N): "
      sync_response = STDIN.gets.chomp.downcase

      if sync_response == 'y' || sync_response == 'yes'
        # Find users enrolled in the affected courses
        affected_user_ids = Enrollment.where(course_id: affected_course_ids)
                                      .distinct
                                      .pluck(:user_id)

        # Also find users via meeting times (for Google Calendar events)
        meeting_time_ids = MeetingTime.where(course_id: affected_course_ids).pluck(:id)
        calendar_user_ids = GoogleCalendarEvent.where(meeting_time_id: meeting_time_ids)
                                               .joins(google_calendar: :oauth_credential)
                                               .pluck("oauth_credentials.user_id")
                                               .uniq

        all_user_ids = (affected_user_ids + calendar_user_ids).uniq

        puts "\nFound #{all_user_ids.count} users with affected courses"

        queued_count = 0
        all_user_ids.each do |user_id|
          user = User.find_by(id: user_id)
          next unless user&.google_credential&.google_calendar

          GoogleCalendarSyncJob.perform_later(user, force: true)
          queued_count += 1
        end

        puts "Queued #{queued_count} calendar sync jobs"
      end
    end

    puts "\nDone!"
  end

  # Keep old task name as alias for backwards compatibility
  desc "Alias for fix_formatting (deprecated)"
  task fix_roman_numerals: :fix_formatting
end
