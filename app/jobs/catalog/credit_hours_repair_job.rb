# frozen_string_literal: true

module Catalog
  # Corrects one term's section credit hours (Catalog::CreditHoursRepair).
  # The catalog:repair_credit_hours task enqueues it for each imported term.
  class CreditHoursRepairJob < ApplicationJob
    queue_as :low

    # Never change this string. Solid Queue puts it in every lock key.
    CONCURRENCY_GROUP = "Catalog::CreditHoursRepairJob"

    # One term at a time, so the catalog requests to Banner stay paced.
    limits_concurrency to: 1, group: CONCURRENCY_GROUP, key: ->(*) { "credit_hours_repair" }, duration: 1.hour

    def perform(term_uid)
      term = Term.find_by(uid: term_uid)
      return Rails.logger.warn("[Catalog::CreditHoursRepairJob] No term #{term_uid}") if term.nil?

      counts = CreditHoursRepair.call(term)
      Rails.logger.info "[Catalog::CreditHoursRepairJob] #{term.name}: #{counts[:changed]} of #{counts[:checked]} changed"
    end
  end
end
