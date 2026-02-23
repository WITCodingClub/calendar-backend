# frozen_string_literal: true

class EnsureFutureTermsJob < ApplicationJob
  queue_as :default

  # Ensures current term and N terms ahead exist (default: 2 terms in the future)
  def perform(terms_ahead: 6)
    # Determine current term
    today = Time.zone.today
    current_year = today.year
    current_season = if today.month >= 8
                       :fall
                     elsif today.month >= 6
                       :summer
                     else
                       :spring
                     end

    # Generate list of terms to ensure (current + terms_ahead)
    terms_to_ensure = []
    year = current_year
    season = current_season

    # Add current term + future terms
    (terms_ahead + 1).times do
      terms_to_ensure << { year: year, season: season }

      # Calculate next term
      case season
      when :spring
        season = :summer
      when :summer
        season = :fall
      when :fall
        season = :spring
        year += 1
      end
    end

    # Create missing terms
    terms_to_ensure.each do |term_attrs|
      next if Term.exists?(year: term_attrs[:year], season: term_attrs[:season])

      # Generate UID based on term pattern:
      # Fall [year] → [year+1]10
      # Spring [year] → [year]20
      # Summer [year] → [year]30
      uid = case term_attrs[:season].to_sym
            when :fall
              ((term_attrs[:year] + 1) * 100) + 10
            when :spring
              (term_attrs[:year] * 100) + 20
            when :summer
              (term_attrs[:year] * 100) + 30
            end

      Term.create!(
        year: term_attrs[:year],
        season: term_attrs[:season],
        uid: uid
      )

      Rails.logger.info "Created term: #{term_attrs[:season].capitalize} #{term_attrs[:year]} (uid: #{uid})"
    end
  end

end
