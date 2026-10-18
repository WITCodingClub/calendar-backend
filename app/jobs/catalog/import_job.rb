# frozen_string_literal: true

module Catalog
  class ImportJob < ApplicationJob
    queue_as :low

    def perform(term_uid)
      Rails.logger.info "[Catalog::ImportJob] Starting import for term #{term_uid}"

      result = Catalog::LeopardWebClient.get_course_catalog(term: term_uid)

      unless result[:success]
        Rails.logger.error "[Catalog::ImportJob] Failed to fetch courses: #{result[:error]}"
        raise "Failed to fetch course catalog: #{result[:error]}"
      end

      courses = result[:courses]
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
    rescue => e
      Term.where(uid: term_uid).update_all(catalog_import_failed: true)
      raise
    ensure
      Term.where(uid: term_uid).update_all(catalog_importing: false)
    end
  end
end
