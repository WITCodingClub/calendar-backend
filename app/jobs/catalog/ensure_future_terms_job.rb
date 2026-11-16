# frozen_string_literal: true

module Catalog
  class Catalog::EnsureFutureTermsJob < ApplicationJob
    queue_as :default

    def perform(terms_ahead: 6)
      uids = [ current_uid ]
      terms_ahead.times { uids << TermCode.next_term(uids.last) }
      existing = Term.where(uid: uids).pluck(:uid).to_set

      uids.each do |uid|
        next if existing.include?(uid)

        term = Term.create!(uid: uid, **TermCode.year_and_season(uid))
        Rails.logger.info "[Catalog::EnsureFutureTermsJob] Created term: #{term.season.capitalize} #{term.year} (uid: #{uid})"
      end
    end

    private

    # The season of today by month: fall from August, summer from June,
    # spring before that.
    def current_uid
      today = Time.zone.today
      season = if today.month >= 8 then :fall
      elsif today.month >= 6 then :summer
      else :spring
      end
      TermCode.for(today.year, season)
    end
  end
end
