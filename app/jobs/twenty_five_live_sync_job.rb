# frozen_string_literal: true

class TwentyFiveLiveSyncJob < ApplicationJob
  queue_as :default

  def perform
    External::TwentyFiveLiveService.call!
  end
end
