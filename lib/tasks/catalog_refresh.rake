# frozen_string_literal: true

namespace :catalog do
  desc "Refreshes the course catalog for a given term from LeopardWeb, preserving user enrollments."
  task :refresh, [:term_uid] => :environment do |_, args|
    term_uid = args[:term_uid]
    raise "Usage: rake catalog:refresh[term_uid]" unless term_uid

    term = Term.find_by(uid: term_uid)
    raise "Term with UID #{term_uid} not found." unless term

    puts "Starting catalog refresh for term #{term.name} (#{term_uid})..."
    puts "WARNING: This will delete all existing courses for this term and re-import them."
    puts "User enrollments will be backed up and restored."
    puts "Press CTRL-C to cancel."
    5.downto(1) do |i|
      print "Continuing in #{i}..."
      sleep 1
      print "\r"
    end

    # == Step 1: Backup enrollments for the term ==
    puts "\n\nStep 1: Backing up enrollments for term #{term.name}..."
    backup_count = 0
    error_count = 0
    snapshot_reason = "Catalog refresh for term #{term.name} on #{Time.current.to_date}"
    enrollments_to_backup = Enrollment.includes(:user, :course, course: [:term, :faculties]).where(term_id: term.id)

    enrollments_to_backup.find_each do |enrollment|
      begin
        course = enrollment.course
        next unless course # Skip if enrollment is already orphaned

        EnrollmentSnapshot.create!(
          user_id: enrollment.user_id,
          term_id: enrollment.term_id,
          crn: course.crn,
          subject: course.subject,
          course_number: course.course_number,
          title: course.title,
          section_number: course.section_number,
          schedule_type: course.schedule_type,
          credit_hours: course.credit_hours,
          faculty_data: course.faculties.map { |f| { first_name: f.first_name, last_name: f.last_name, email: f.email } },
          snapshot_reason: snapshot_reason
        )
        backup_count += 1
      rescue => e
        puts "\nError backing up enrollment #{enrollment.id}: #{e.message}"
        error_count += 1
      end
    end
    puts "Backed up #{backup_count} enrollments with #{error_count} errors."

    # == Step 2: Delete course data for the term ==
    puts "\nStep 2: Deleting course data for term #{term.name}..."
    courses_for_term = Course.where(term: term)
    course_ids_for_term = courses_for_term.pluck(:id)

    puts "Orphaning Google Calendar events..."
    meeting_time_ids = MeetingTime.where(course_id: course_ids_for_term).pluck(:id)
    GoogleCalendarEvent.where(meeting_time_id: meeting_time_ids).update_all(meeting_time_id: nil)

    puts "Deleting meeting times..."
    MeetingTime.where(course_id: course_ids_for_term).delete_all

    puts "Deleting enrollments..."
    Enrollment.where(term_id: term.id).delete_all

    puts "Deleting course-faculty associations..."
    # Use destroy_all to trigger callbacks if any, or just clear associations
    courses_for_term.each { |c| c.faculties.clear }

    puts "Deleting courses..."
    delete_count = courses_for_term.delete_all
    puts "Deleted #{delete_count} courses."

    # == Step 3: Re-import the catalog for the term ==
    puts "\nStep 3: Importing fresh catalog data from LeopardWeb..."
    CatalogImportJob.perform_now(term_uid)

    # == Step 4: Restore enrollments for the term ==
    puts "\nStep 4: Restoring enrollments for term #{term.name}..."
    restored_count = 0
    restore_error_count = 0
    not_found_count = 0
    snapshots_to_restore = EnrollmentSnapshot.where(term_id: term.id, snapshot_reason: snapshot_reason)

    snapshots_to_restore.includes(:user, :term).find_each do |snapshot|
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
    puts "Restored #{restored_count} enrollments. #{not_found_count} courses not found. #{restore_error_count} errors."

    # == Step 5: Clean up snapshots for the term ==
    puts "\nStep 5: Cleaning up backup snapshots..."
    snapshot_delete_count = snapshots_to_restore.delete_all
    puts "Deleted #{snapshot_delete_count} snapshots."

    puts "\nCatalog refresh completed for term #{term.name}."
  end

  desc "Refreshes the course catalog for ALL terms from LeopardWeb."
  task :refresh_all => :environment do
    puts "Starting catalog refresh for ALL terms..."

    terms_to_refresh = Term.all

    if terms_to_refresh.empty?
      puts "No terms found in the database. Nothing to refresh."
      next
    end

    puts "Found #{terms_to_refresh.count} terms to refresh: #{terms_to_refresh.map(&:name).join(', ')}"
    puts "This will take a long time."
    puts "Press CTRL-C to cancel."
    5.downto(1) do |i|
      print "Continuing in #{i}..."
      sleep 1
      print "\r"
    end

    terms_to_refresh.each do |term|
      puts "\n" + "="*80
      puts "Refreshing term: #{term.name} (#{term.uid})"
      puts "="*80

      begin
        Rake::Task["catalog:refresh"].invoke(term.uid.to_s)
        Rake::Task["catalog:refresh"].reenable
      rescue => e
        puts "ERROR: Failed to refresh term #{term.name} (#{term.uid}). Reason: #{e.message}"
        puts "Skipping to next term."
      end
    end

    puts "\n" + "="*80
    puts "Completed refresh for all terms."
  end
end
end
