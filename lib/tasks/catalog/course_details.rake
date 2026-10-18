# frozen_string_literal: true

namespace :catalog do
  desc "Once: load course descriptions and prerequisites for every imported term, newest first"
  task backfill_course_details: :environment do
    # Every course gets a row first, so prerequisites can link to courses
    # that only old terms offered.
    seeded = Catalog::CourseDetailsSync.seed(Course.all)
    puts "Seeded #{seeded} courses."

    terms = Term.where(id: Course.select(:term_id)).order(uid: :desc)
    terms.each { |term| Catalog::CourseDetailsSyncJob.perform_later(term.uid) }

    # The job runs one term at a time. The newest term wins, so older terms
    # only fill the courses that newer terms do not offer.
    puts "Enqueued Catalog::CourseDetailsSyncJob for #{terms.size} terms: #{terms.map(&:uid).join(', ')}"
  end
end
