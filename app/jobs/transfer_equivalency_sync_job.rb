# frozen_string_literal: true

class TransferEquivalencySyncJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "[TransferEquivalencySyncJob] Starting transfer equivalency sync"

    result = Transfer::EquivalencySyncService.call

    Rails.logger.info "[TransferEquivalencySyncJob] Sync completed: " \
                      "#{result[:universities_synced]} universities, " \
                      "#{result[:courses_synced]} courses, " \
                      "#{result[:equivalencies_synced]} equivalencies synced"

    if result[:errors].any?
      Rails.logger.warn "[TransferEquivalencySyncJob] #{result[:errors].size} errors: #{result[:errors].first(5).join('; ')}"
    end

    result
  end

end
