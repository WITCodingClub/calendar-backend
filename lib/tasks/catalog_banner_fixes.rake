# frozen_string_literal: true

namespace :catalog do
  desc "Fetch Banner's lecture and lab pairs for the terms imported before section links existed"
  task backfill_section_links: :environment do
    # Current and future terms first: students plan with them now.
    current = Term.current_and_future.to_a + Term.active.to_a
    older   = Term.reverse_chronological.where.not(id: current.map(&:id)).to_a
    terms   = (current.uniq + older).select { |term| term.courses.where(is_section_linked: true).exists? }

    terms.each { |term| Catalog::SectionLinksSyncJob.perform_later(term.uid) }
    puts "Enqueued Catalog::SectionLinksSyncJob for #{terms.size} terms: #{terms.map(&:uid).join(', ')}"
  end
end

namespace :catalog do
  desc "Correct section credit hours (labs to nil) for imported terms, current and future terms first"
  task repair_credit_hours: :environment do
    current = (Term.current_and_future.to_a + Term.active.to_a).uniq
    older   = Term.reverse_chronological.where.not(id: current.map(&:id)).to_a
    terms   = (current + older).select { |term| term.courses.exists? }

    terms.each { |term| Catalog::CreditHoursRepairJob.perform_later(term.uid) }
    puts "Enqueued Catalog::CreditHoursRepairJob for #{terms.size} terms: #{terms.map(&:uid).join(', ')}"
  end
end
