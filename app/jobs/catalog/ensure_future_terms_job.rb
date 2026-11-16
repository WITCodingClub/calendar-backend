# frozen_string_literal: true

module Catalog
  class EnsureFutureTermsJob < ApplicationJob
    queue_as :default

    def perform(terms_ahead: 6)
      uids = [ TermCode.for_date(Time.zone.today) ]
      terms_ahead.times { uids << TermCode.next_term(uids.last) }
      existing = Term.where(uid: uids).pluck(:uid).to_set

      uids.each do |uid|
        next if existing.include?(uid)

        term = Term.create!(uid: uid, **TermCode.year_and_season(uid))
        Rails.logger.info "[Catalog::EnsureFutureTermsJob] Created term: #{term.season.capitalize} #{term.year} (uid: #{uid})"
      end
    end
  end
end
