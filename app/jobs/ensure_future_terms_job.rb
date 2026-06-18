# frozen_string_literal: true

class EnsureFutureTermsJob < ApplicationJob
  queue_as :default

  def perform(terms_ahead: 6)
    today          = Time.zone.today
    current_year   = today.year
    current_season = if today.month >= 8
                       :fall
    elsif today.month >= 6
                       :summer
    else
                       :spring
    end

    terms_to_ensure = []
    year   = current_year
    season = current_season

    (terms_ahead + 1).times do
      terms_to_ensure << { year: year, season: season }

      season, year = case season
      when :spring then [ :summer, year ]
      when :summer then [ :fall,   year ]
      when :fall   then [ :spring, year + 1 ]
      end
    end

    existing_terms = Term.where(year: terms_to_ensure.map { |t| t[:year] })
                         .each_with_object({}) { |t, h| h[[ t.year, t.season.to_sym ]] = true }

    terms_to_ensure.each do |attrs|
      next if existing_terms[[ attrs[:year], attrs[:season].to_sym ]]

      uid = case attrs[:season].to_sym
      when :fall   then ((attrs[:year] + 1) * 100) + 10
      when :spring then (attrs[:year] * 100) + 20
      when :summer then (attrs[:year] * 100) + 30
      end

      Term.create!(year: attrs[:year], season: attrs[:season], uid: uid)
      Rails.logger.info "[EnsureFutureTermsJob] Created term: #{attrs[:season].capitalize} #{attrs[:year]} (uid: #{uid})"
    end
  end
end
