# frozen_string_literal: true

module Catalog
  # Imports every section of one term from Banner's class search.
  #
  # The job owns the import flags of the term, which the admin pages show:
  # catalog_importing while it runs, and catalog_import_failed when it raised.
  # Start it with ImportJob.enqueue(term), which shows the term as importing
  # before the job is in the queue, or with perform_now.
  class ImportJob < ApplicationJob
    queue_as :low

    # Sets the flags first, so a job that ends before this method returns
    # cannot leave the term marked as importing.
    def self.enqueue(term)
      job = new(term.uid)
      term.update!(catalog_importing: true, catalog_import_failed: false, catalog_import_job_id: job.job_id)
      job.enqueue
      job
    end

    def perform(term_uid)
      terms = Term.where(uid: term_uid)
      terms.update_all(catalog_importing: true, catalog_import_failed: false)
      Rails.logger.info "[Catalog::ImportJob] Starting import for term #{term_uid}"

      courses = Catalog::LeopardWebClient.get_course_catalog(term: term_uid)
      Rails.logger.info "[Catalog::ImportJob] Fetched #{courses.count} courses for term #{term_uid}"

      if courses.empty?
        Rails.logger.warn "[Catalog::ImportJob] No courses found for term #{term_uid}"
        return { total: 0, processed: 0, failed: 0, failed_courses: [], created: 0, updated: 0, unchanged: 0 }
      end

      result = Catalog::Importer.new(courses).call!
      # Descriptions and prerequisites come from four more Banner pages per
      # course, so they load in their own job, after the sections exist.
      Catalog::CourseDetailsSyncJob.perform_later(term_uid)

      # The import gives link identifiers only. Banner's real pairs come from
      # one request for each linked section, so they run in their own job.
      Catalog::SectionLinksSyncJob.perform_later(term_uid)

      Rails.logger.info "[Catalog::ImportJob] Completed import for term #{term_uid}: " \
                        "#{result[:created]} added, #{result[:updated]} updated, #{result[:unchanged]} unchanged"
      result
    rescue StandardError
      terms.update_all(catalog_import_failed: true)
      raise
    ensure
      terms.update_all(catalog_importing: false)
    end
  end
end
