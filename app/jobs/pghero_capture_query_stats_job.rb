# frozen_string_literal: true

class PgheroCaptureQueryStatsJob < ApplicationJob
  queue_as :low

  def perform
    PgHero.capture_query_stats
  rescue PgHero::NotEnabled => e
    Rails.logger.info("PgHero query stats not enabled: #{e.message}")
  end

end
