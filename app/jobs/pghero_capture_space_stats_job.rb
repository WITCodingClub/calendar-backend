# frozen_string_literal: true

class PgheroCaptureSpaceStatsJob < ApplicationJob
  queue_as :low

  def perform
    PgHero.capture_space_stats
  rescue PgHero::NotEnabled => e
    Rails.logger.info("PgHero space stats not enabled: #{e.message}")
  end

end
