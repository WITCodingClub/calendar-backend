# frozen_string_literal: true

namespace :catalog do
  desc "Refresh the course catalog for a given term from LeopardWeb, preserving user enrollments."
  task :refresh, [ :term_uid ] => :environment do |_, args|
    term_uid = args[:term_uid]
    raise "Usage: rake catalog:refresh[term_uid]" unless term_uid

    term = Term.find_by(uid: term_uid)
    raise "Term with UID #{term_uid} not found." unless term

    puts "Starting catalog refresh for term #{term.name} (#{term_uid})..."
    puts "WARNING: This will delete all existing courses for this term and re-import them."
    puts "User enrollments will be backed up and restored."
    puts "Press CTRL-C to cancel."
    5.downto(1) { |i| print "Continuing in #{i}...\r"; sleep 1 }

    # Step 1: Backup enrollments
    puts "\n\nStep 1: Backing up enrollments for term #{term.name}..."
    backup_count     = 0
    error_count      = 0
    snapshot_reason  = "Catalog refresh for term #{term.name} on #{Time.current.to_date}"
    enrollments      = Enrollment.includes(:user, :course, course: [ :term, :faculties ]).where(term_id: term.id)

    enrollments.find_each do |enrollment|
      begin
        course = enrollment.course
        next unless course

        EnrollmentSnapshot.create!(
          user_id:       enrollment.user_id,
          term_id:       enrollment.term_id,
          crn:           course.crn,
          subject:       course.subject,
          course_number: course.course_number,
          title:         course.title,
          section_number: course.section_number,
          schedule_type: course.schedule_type,
          credit_hours:  course.credit_hours,
          faculty_data:  course.faculties.map { |f| { first_name: f.first_name, last_name: f.last_name, email: f.email } },
          snapshot_reason: snapshot_reason
        )
        backup_count += 1
      rescue => e
        puts "\nError backing up enrollment #{enrollment.id}: #{e.message}"
        error_count += 1
      end
    end
    puts "Backed up #{backup_count} enrollments with #{error_count} errors."

    # Step 2: Pre-flight fetch — get the fresh catalog BEFORE deleting anything.
    # If the scrape fails or returns no courses (e.g. LeopardWeb markup changed),
    # abort now so we never wipe a term's data with nothing to replace it.
    puts "\nStep 2: Fetching fresh catalog data from LeopardWeb (pre-flight)..."
    result = LeopardWebService.get_course_catalog(term: term_uid)
    unless result[:success]
      raise "Aborting: failed to fetch catalog for term #{term.name}: #{result[:error]}. No data was deleted."
    end

    fresh_courses = result[:courses] || []
    if fresh_courses.empty?
      raise "Aborting: LeopardWeb returned 0 courses for term #{term.name}. No data was deleted."
    end
    puts "Fetched #{fresh_courses.count} courses. Proceeding with refresh."

    # Steps 3–4 run in a single transaction so any failure during delete/import
    # rolls back the deletions, leaving the existing catalog intact.
    restored_count      = 0
    restore_error_count = 0
    not_found_count     = 0
    snapshots           = EnrollmentSnapshot.where(term_id: term.id, snapshot_reason: snapshot_reason)

    ActiveRecord::Base.transaction do
      # Step 3: Delete course data
      puts "\nStep 3: Deleting course data for term #{term.name}..."
      courses_for_term    = Course.where(term: term)
      course_ids_for_term = courses_for_term.pluck(:id)

      puts "Orphaning Google Calendar events..."
      meeting_time_ids = Course::MeetingTime.where(course_id: course_ids_for_term).pluck(:id)
      GoogleCalendarEvent.where(meeting_time_id: meeting_time_ids).update_all(meeting_time_id: nil)

      puts "Deleting meeting times..."
      Course::MeetingTime.where(course_id: course_ids_for_term).delete_all

      puts "Deleting enrollments..."
      Enrollment.where(term_id: term.id).delete_all

      puts "Deleting course-faculty associations..."
      courses_for_term.each { |c| c.faculties.clear }

      puts "Deleting courses..."
      delete_count = courses_for_term.delete_all
      puts "Deleted #{delete_count} courses."

      # Re-import using the already-fetched data (no second HTTP call).
      puts "\nImporting fresh catalog data..."
      CatalogImportService.new(fresh_courses).call!

      # Step 4: Restore enrollments
      puts "\nStep 4: Restoring enrollments for term #{term.name}..."
      snapshots.includes(:user, :term).find_each do |snapshot|
        begin
          course = Course.find_by(crn: snapshot.crn, term_id: snapshot.term_id)
          if course
            Enrollment.find_or_create_by!(user_id: snapshot.user_id, course_id: course.id, term_id: snapshot.term_id)
            restored_count += 1
          else
            not_found_count += 1
          end
        rescue => e
          puts "\nError restoring enrollment for user #{snapshot.user_id}, CRN #{snapshot.crn}: #{e.message}"
          restore_error_count += 1
        end
      end
    end
    puts "Restored #{restored_count} enrollments. #{not_found_count} courses not found. #{restore_error_count} errors."

    # Step 5: Clean up snapshots
    puts "\nStep 5: Cleaning up backup snapshots..."
    puts "Deleted #{snapshots.delete_all} snapshots."

    # Step 6: Mark users for calendar sync
    puts "\nStep 6: Marking users for calendar sync..."
    sync_count = User.joins(:enrollments).where(enrollments: { term_id: term.id }).distinct.update_all(calendar_needs_sync: true)
    puts "Marked #{sync_count} users for calendar sync."

    # Step 7: Clean up orphaned calendar events
    puts "\nStep 7: Cleaning up orphaned calendar events..."
    result = CleanupOrphanedCalendarEventsJob.perform_now
    puts "Cleaned up #{result[:deleted]} orphaned events (#{result[:errors]} errors)."

    puts "\nCatalog refresh completed for term #{term.name}."
  end

  desc "Refresh the course catalog for ALL terms from LeopardWeb."
  task refresh_all: :environment do
    puts "Starting catalog refresh for ALL terms..."

    terms = Term.all
    if terms.empty?
      puts "No terms found in the database. Nothing to refresh."
      next
    end

    puts "Found #{terms.count} terms to refresh: #{terms.map(&:name).join(', ')}"
    puts "Press CTRL-C to cancel."
    5.downto(1) { |i| print "Continuing in #{i}...\r"; sleep 1 }

    terms.each do |term|
      puts "\n" + "=" * 80
      puts "Refreshing term: #{term.name} (#{term.uid})"
      puts "=" * 80

      begin
        Rake::Task["catalog:refresh"].invoke(term.uid.to_s)
        Rake::Task["catalog:refresh"].reenable
      rescue => e
        puts "ERROR: Failed to refresh term #{term.name} (#{term.uid}). Reason: #{e.message}"
        puts "Skipping to next term."
      end
    end

    puts "\n" + "=" * 80
    puts "Completed refresh for all terms."
  end

  desc "Trigger immediate calendar syncs for all users enrolled in a term"
  task :sync_calendars, [ :term_uid ] => :environment do |_, args|
    term_uid = args[:term_uid]
    raise "Usage: rake catalog:sync_calendars[term_uid]" unless term_uid

    term = Term.find_by(uid: term_uid)
    raise "Term with UID #{term_uid} not found." unless term

    users = User.joins(:enrollments)
                .where(enrollments: { term_id: term.id })
                .joins(:oauth_credentials)
                .where.not(oauth_credentials: { id: nil })
                .distinct

    puts "Queueing calendar syncs for #{users.count} users in term #{term.name}..."

    users.find_each do |user|
      GoogleCalendarSyncJob.perform_later(user)
      puts "  Queued sync for user #{user.id} (#{user.email})"
    end

    puts "Done! Syncs queued for processing."
  end
end
