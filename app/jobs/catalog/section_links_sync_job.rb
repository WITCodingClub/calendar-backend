# frozen_string_literal: true

module Catalog
  # Fetches Banner's lecture and lab pairs for every linked section in a term
  # (Catalog::SectionLinksSync). Catalog::ImportJob enqueues it after a new
  # import, and the catalog:backfill_section_links task enqueues it for the
  # terms imported before.
  class SectionLinksSyncJob < ApplicationJob
    queue_as :low

    # Never change this string. Solid Queue puts it in every lock key.
    CONCURRENCY_GROUP = "Catalog::SectionLinksSyncJob"

    # One term at a time, so the requests to Banner stay paced. A term takes a
    # few minutes, so a waiting job keeps its turn for longer than the default.
    limits_concurrency to: 1, group: CONCURRENCY_GROUP, key: ->(*) { "section_links_sync" }, duration: 2.hours

    def perform(term_uid)
      term = Term.find_by(uid: term_uid)
      return Rails.logger.warn("[Catalog::SectionLinksSyncJob] No term #{term_uid}") if term.nil?

      counts = SectionLinksSync.for_term(term)
      Rails.logger.info "[Catalog::SectionLinksSyncJob] #{term.name}: #{counts[:synced]} synced, #{counts[:failed]} failed"
    end
  end
end
