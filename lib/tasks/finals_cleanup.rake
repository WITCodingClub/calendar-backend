# frozen_string_literal: true

namespace :finals do
  desc "Delete FinalExam/FinalsSchedule records for PAST terms only. " \
       "Current and future terms are always protected. Safe by default (dry run); " \
       "pass CONFIRM=1 to apply. Optionally keep extra past terms with KEEP=\"season-year,...\"."
  task reset: :environment do
    # Default to a dry run — only an explicit CONFIRM=1 actually deletes.
    dry_run = ENV["CONFIRM"] != "1"
    puts dry_run ? "DRY RUN — no changes will be made (pass CONFIRM=1 to apply)." : "Deleting finals data..."
    puts

    # Always protect current and future terms so this never wipes live finals,
    # regardless of when the task is run.
    protected_terms = Term.current_and_future.to_a

    # Optionally protect additional past terms, e.g. KEEP="summer-2025,fall-2025".
    ENV["KEEP"].to_s.split(",").map(&:strip).reject(&:blank?).each do |token|
      season, year = token.split("-", 2)
      term = Term.find_by(season: season&.downcase, year: year.to_i)
      if term
        protected_terms << term
      else
        puts "  Warning: KEEP term '#{token}' not found — nothing to protect"
      end
    end

    protected_terms.uniq!
    protected_terms.each do |term|
      puts "  Keeping: #{term.season.to_s.capitalize} #{term.year} (id=#{term.id})"
    end
    puts

    protected_ids  = protected_terms.map(&:id)
    terms_to_wipe  = Term.all.reject { |t| protected_ids.include?(t.id) }
    terms_with_data = terms_to_wipe.select do |t|
      FinalExam.where(term: t).exists? || FinalsSchedule.where(term: t).exists?
    end

    if terms_with_data.empty?
      puts "No finals data found outside the protected terms. Nothing to do."
      exit
    end

    total_exams     = 0
    total_schedules = 0

    terms_with_data.each do |term|
      exam_count     = FinalExam.where(term: term).count
      schedule_count = FinalsSchedule.where(term: term).count
      total_exams     += exam_count
      total_schedules += schedule_count

      label = "#{term.season.capitalize} #{term.year} (id=#{term.id})"
      puts "  #{label}: #{exam_count} exam(s), #{schedule_count} schedule upload(s)"

      unless dry_run
        FinalExam.where(term: term).destroy_all
        FinalsSchedule.where(term: term).destroy_all
      end
    end

    puts
    if dry_run
      puts "Would delete: #{total_exams} FinalExam(s) and #{total_schedules} FinalsSchedule(s) across #{terms_with_data.size} term(s)."
      puts "Run with CONFIRM=1 to apply."
    else
      puts "Deleted #{total_exams} FinalExam(s) and #{total_schedules} FinalsSchedule(s) across #{terms_with_data.size} term(s)."
    end
  end
end
