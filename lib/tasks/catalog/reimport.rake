# frozen_string_literal: true

namespace :catalog do
  desc "Import every term again from Banner, newest first, one term at a time. " \
       "ENV: FROM and TO (term uids) limit the terms; DRY_RUN=1 prints the plan only."
  task reimport_all_terms: :environment do
    from = ENV["FROM"]
    to   = ENV["TO"]

    # DRY_RUN=0 or false runs for real. Only a true value prints the plan.
    if ActiveModel::Type::Boolean.new.cast(ENV["DRY_RUN"])
      # One request for the term list. The plan is the same one the job builds.
      plan = Catalog::BannerThrottle.with_budget(:job) { Catalog::ReimportPlan.new(from: from, to: to).call }

      puts "Would import #{plan.term_uids.size} terms, newest first:"
      plan.term_uids.each { |uid| puts "  #{uid}" }
      puts "Banner lists these terms, but they are not in the database (skipped): #{plan.missing_in_database.join(', ')}" if plan.missing_in_database.any?
      puts "These terms are in the database, but Banner no longer lists them (skipped): #{plan.missing_in_banner.join(', ')}" if plan.missing_in_banner.any?
      next
    end

    Catalog::ReimportAllTermsJob.perform_later(from: from, to: to)
    puts "Queued Catalog::ReimportAllTermsJob. It imports one term at a time, newest first."
    puts "Follow it in the logs: grep 'Catalog::ReimportAllTermsJob'"
  end
end
