# frozen_string_literal: true

namespace :course_data do
  desc "Backup all enrollments to snapshots table before course data cleanup"
  task backup_enrollments: :environment do
    puts "Starting enrollment backup..."
    
    backup_count = 0
    error_count = 0
    
    Enrollment.includes(:user, :course, course: [:term, :faculties]).find_each do |enrollment|
      begin
        course = enrollment.course
        
        # Create snapshot with all course details
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
          faculty_data: course.faculties.map { |f| 
            { 
              first_name: f.first_name, 
              last_name: f.last_name, 
              email: f.email 
            } 
          },
          snapshot_reason: "Pre-CRN-uniqueness-fix backup"
        )
        
        backup_count += 1
        
        if backup_count % 100 == 0
          print "."
        end
      rescue => e
        puts "\nError backing up enrollment #{enrollment.id}: #{e.message}"
        error_count += 1
      end
    end
    
    puts "\n✅ Backed up #{backup_count} enrollments"
    puts "❌ #{error_count} errors" if error_count > 0
    
    puts "\nVerifying backup integrity..."
    enrollment_count = Enrollment.count
    snapshot_count = EnrollmentSnapshot.count
    
    if enrollment_count == snapshot_count
      puts "✅ Backup verified: #{snapshot_count} snapshots created"
    else
      puts "⚠️  Warning: Enrollment count (#{enrollment_count}) doesn't match snapshot count (#{snapshot_count})"
    end
  end
  
  desc "Delete all course data while preserving other records"
  task delete_course_data: :environment do
    puts "⚠️  WARNING: This will delete all course-related data!"
    puts "Make sure you have run 'rails course_data:backup_enrollments' first!"
    print "Type 'DELETE COURSES' to confirm: "
    
    confirmation = STDIN.gets.chomp
    unless confirmation == "DELETE COURSES"
      puts "Aborted."
      exit
    end
    
    puts "\nStarting course data deletion..."
    
    # Disconnect calendar events (orphan them)
    puts "Orphaning Google Calendar events..."
    GoogleCalendarEvent.where.not(meeting_time_id: nil).update_all(
      meeting_time_id: nil
    )
    
    # Delete in correct order to avoid foreign key constraints
    puts "Deleting meeting times..."
    deleted_meeting_times = MeetingTime.delete_all
    
    puts "Deleting enrollments..."
    deleted_enrollments = Enrollment.delete_all
    
    puts "Deleting course-faculty associations..."
    ActiveRecord::Base.connection.execute("DELETE FROM courses_faculties")
    
    puts "Deleting courses..."
    deleted_courses = Course.delete_all
    
    puts "\n✅ Deletion complete:"
    puts "  - #{deleted_courses} courses deleted"
    puts "  - #{deleted_enrollments} enrollments deleted"
    puts "  - #{deleted_meeting_times} meeting times deleted"
    puts "  - Google Calendar events orphaned (preserved for reference)"
  end
  
  desc "Restore enrollments from snapshots after re-importing courses"
  task restore_enrollments: :environment do
    puts "Starting enrollment restoration from snapshots..."
    
    restored_count = 0
    error_count = 0
    not_found_count = 0
    
    EnrollmentSnapshot.includes(:user, :term).find_each do |snapshot|
      begin
        # Find the course by CRN AND term
        course = Course.find_by(crn: snapshot.crn, term_id: snapshot.term_id)
        
        if course
          # Create enrollment
          enrollment = Enrollment.find_or_create_by!(
            user_id: snapshot.user_id,
            course_id: course.id,
            term_id: snapshot.term_id
          )
          
          restored_count += 1
          
          if restored_count % 100 == 0
            print "."
          end
        else
          puts "\n⚠️  Course not found: CRN #{snapshot.crn} in term #{snapshot.term.name}"
          not_found_count += 1
        end
      rescue => e
        puts "\nError restoring enrollment for user #{snapshot.user_id}, CRN #{snapshot.crn}: #{e.message}"
        error_count += 1
      end
    end
    
    puts "\n\n✅ Restoration complete:"
    puts "  - #{restored_count} enrollments restored"
    puts "  - #{not_found_count} courses not found (may need to import those terms)"
    puts "  - #{error_count} errors" if error_count > 0
    
    # Trigger calendar syncs for affected users
    if restored_count > 0
      puts "\nTriggering calendar syncs for affected users..."
      User.joins(:enrollments).distinct.each do |user|
        GoogleCalendarSyncJob.perform_later(user, force: true) if user.google_course_calendar_id.present?
      end
      puts "✅ Calendar sync jobs queued"
    end
  end
  
  desc "Full course data fix workflow"
  task fix_all: :environment do
    puts "Starting full course data fix workflow...\n"
    
    # Step 1: Backup
    Rake::Task["course_data:backup_enrollments"].invoke
    
    puts "\n" + "="*50
    puts "Step 1 complete. Next steps:"
    puts "1. Run migrations: rails db:migrate"
    puts "2. Deploy code changes"
    puts "3. Run: rails course_data:delete_course_data"
    puts "4. Re-import all course data"
    puts "5. Run: rails course_data:restore_enrollments"
  end
end