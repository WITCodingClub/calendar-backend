# frozen_string_literal: true

module Catalog
  # Imports every term again, one term at a time (catalog:reimport_all_terms).
  #
  # The first run builds the plan (Catalog::ReimportPlan). Each run imports one
  # term with Catalog::ImportJob, logs what changed, and enqueues the next term.
  # Banner sees one import at a time, and every request gets the job budget of
  # Catalog::BannerThrottle. A term that fails is logged and reported, and the
  # run goes on to the next term.
  #
  # An import only adds and updates sections. It deletes no section and changes
  # no enrollment. It does replace the meeting times of a section whose times
  # changed in Banner, the same as an import from the admin page.
  class ReimportAllTermsJob < ApplicationJob
    queue_as :low

    # Solid Queue puts this string in every lock key. Never change it.
    CONCURRENCY_GROUP = "ReimportAllTermsJob"

    # One run at a time. A second run waits until the first one ends.
    limits_concurrency to: 1, group: CONCURRENCY_GROUP, key: ->(*) { "reimport_all_terms" }

    LOG_TAG = "[Catalog::ReimportAllTermsJob]"

    def perform(term_uids: nil, from: nil, to: nil)
      term_uids = plan(from: from, to: to) if term_uids.nil?
      return Rails.logger.info("#{LOG_TAG} Done: no terms left") if term_uids.empty?

      uid, *rest = term_uids
      import(uid, remaining: rest.size)

      self.class.perform_later(term_uids: rest) if rest.any?
      Rails.logger.info("#{LOG_TAG} Done: every term in the plan was imported") if rest.empty?
    end

    private

    def plan(from:, to:)
      result = Catalog::ReimportPlan.new(from: from, to: to).call

      Rails.logger.info("#{LOG_TAG} Plan: #{result.term_uids.size} terms, newest first: #{result.term_uids.join(', ')}")
      if result.missing_in_database.any?
        Rails.logger.warn("#{LOG_TAG} Banner lists terms that are not in the database, skipped: #{result.missing_in_database.join(', ')}")
      end
      if result.missing_in_banner.any?
        Rails.logger.warn("#{LOG_TAG} Terms in the database that Banner no longer lists, skipped: #{result.missing_in_banner.join(', ')}")
      end

      result.term_uids
    end

    # The flag shows the term as importing on the admin pages, for this term
    # only. Catalog::ImportJob clears it when it ends, whatever the result.
    def import(uid, remaining:)
      Term.where(uid: uid).update_all(catalog_importing: true, catalog_import_failed: false)
      result = Catalog::ImportJob.perform_now(uid)

      Rails.logger.info(
        "#{LOG_TAG} Term #{uid}: #{result[:created]} added, #{result[:updated]} updated, " \
        "#{result[:unchanged]} unchanged (#{remaining} terms left)"
      )
    rescue StandardError => e
      # The run goes on, so the error is reported here. ImportJob has marked
      # the term catalog_import_failed.
      Rails.error.report(e, handled: true, context: { term_uid: uid })
      Rails.logger.error("#{LOG_TAG} Term #{uid} failed: #{e.class}: #{e.message} (#{remaining} terms left)")
    end
  end
end
