# frozen_string_literal: true

class TwentyFiveLiveSyncJob < ApplicationJob
  queue_as :low

  def perform
    result = TwentyFiveLiveService.call(action: :sync_events)
    Rails.logger.info("[TwentyFiveLiveSyncJob] #{result}")
  end

end
