# frozen_string_literal: true

namespace :catalog do
  desc "Load course details for every imported term, newest first (REFETCH=1 also fetches fresh courses again)"
  task backfill_course_details: :environment do
    # The sync skips a course fetched in the last week. After a new detail
    # column ships, REFETCH=1 fills it for every course now, not in a week.
    if ENV["REFETCH"].present?
      cleared = CatalogCourse.where.not(details_fetched_at: nil).update_all(details_fetched_at: nil) # rubocop:disable Rails/SkipsModelValidations
      puts "Marked #{cleared} courses to fetch again."
    end

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
