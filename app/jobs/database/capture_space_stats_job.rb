# frozen_string_literal: true

module Database
  class CaptureSpaceStatsJob < ApplicationJob
    queue_as :low

    def perform
      PgHero.capture_space_stats
    rescue PgHero::NotEnabled => e
      Rails.logger.info("PgHero space stats not enabled: #{e.message}")
    end
  end
end
