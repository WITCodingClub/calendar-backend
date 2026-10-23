# frozen_string_literal: true

namespace :finals do
  desc "Link each final exam with no course, and a date from today on, to the course " \
       "with the same CRN and term. Then re-sync the calendars of the students in those courses. " \
       "Safe by default (dry run); pass CONFIRM=1 to apply."
  task link_orphans: :environment do
    dry_run = ENV["CONFIRM"] != "1"
    puts dry_run ? "DRY RUN: no changes will be made (pass CONFIRM=1 to apply)." : "Linking final exams..."

    # Past finals are left alone: a forced sync would add them to every
    # student's calendar.
    pairs = FinalExam.orphan
                     .upcoming
                     .joins("INNER JOIN courses ON courses.term_id = final_exams.term_id AND courses.crn = final_exams.crn")
                     .pluck("final_exams.id", "courses.id")
    puts "#{pairs.size} final exam(s) with no course have a matching course."

    course_ids = pairs.map(&:last)
    users = User.joins(:enrollments).where(enrollments: { course_id: course_ids }).distinct
    puts "#{users.count} student(s) take those courses."
    next if dry_run || pairs.empty?

    FinalExam.transaction do
      pairs.each { |exam_id, course_id| FinalExam.find(exam_id).update!(course_id: course_id) }
    end
    users.find_each { |user| CourseCalendars::SyncJob.perform_later(user, force: true) }
    puts "Linked #{pairs.size} final exam(s) and queued #{users.count} calendar sync(s)."
  end
end
