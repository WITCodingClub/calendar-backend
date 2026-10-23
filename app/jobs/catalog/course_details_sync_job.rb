# frozen_string_literal: true

module Catalog
  # Stores Banner's course details for one term (Catalog::CourseDetailsSync).
  # Catalog::ImportJob enqueues it after an import, and Catalog::CourseDataSyncJob
  # every night for the terms it syncs. `bin/rails catalog:backfill_course_details`
  # enqueues it for every term once.
  class CourseDetailsSyncJob < ApplicationJob
    queue_as :low

    # Solid Queue puts this string in every lock key, so it must never change.
    CONCURRENCY_GROUP = "CatalogCourseDetailsSyncJob"

    # One term at a time, so the requests to Banner never pile up.
    limits_concurrency to: 1, group: CONCURRENCY_GROUP, key: ->(*) { "course_details_sync" }, duration: 6.hours

    def perform(term_uid)
      term = Term.find_by(uid: term_uid)
      return Rails.logger.warn("[Catalog::CourseDetailsSyncJob] No term #{term_uid}") if term.nil?

      result = Catalog::CourseDetailsSync.new(term).call
      # The time of a full run, for the MCP advisory (Catalog::Freshness).
      term.update_column(:details_synced_at, Time.current) # rubocop:disable Rails/SkipsModelValidations
      Rails.logger.info "[Catalog::CourseDetailsSyncJob] #{term.name}: #{result.fetched} fetched, " \
                        "#{result.skipped} skipped, #{result.failed} failed"
    end
  end
end
