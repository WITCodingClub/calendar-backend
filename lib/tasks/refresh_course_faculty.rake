# frozen_string_literal: true

namespace :courses do
  # The nightly Catalog::CourseDataSyncJob does the same for the synced terms.
  # Use this for one older term, or to run the sync now.
  desc "Sync each section of a term from Banner: details, rooms, and instructors (default: the terms the nightly sync reads)"
  task :refresh_faculty, [ :term_uid ] => :environment do |_t, args|
    terms = args[:term_uid].present? ? Term.where(uid: args[:term_uid]) : Term.where(uid: Term.synced_uids)
    abort "No terms found to refresh" if terms.none?

    terms.reverse_chronological.each do |term|
      result = Catalog::SectionSync.call_many(term.courses.order(:id).ids)
      puts "#{term.name} (#{term.uid}): #{result[:synced]} sections changed, #{result[:errors]} failed"
    end
  end
end
