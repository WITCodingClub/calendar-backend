# frozen_string_literal: true

namespace :finals do
  # Terms whose data should never be touched by this task.
  KEEP_TERMS = [
    { season: :summer, year: 2025 },
    { season: :fall,   year: 2025 },
  ].freeze

  desc <<~DESC
    Delete all FinalExam and FinalsSchedule records except Summer 2025 and Fall 2025.
    Pass DRY_RUN=1 to preview without deleting.
  DESC
  task reset: :environment do
    dry_run = ENV["DRY_RUN"].present?
    puts dry_run ? "DRY RUN — no changes will be made." : "Deleting finals data..."
    puts

    protected_terms = KEEP_TERMS.filter_map do |t|
      term = Term.find_by(season: t[:season], year: t[:year])
      if term
        puts "  Keeping: #{term.season.capitalize} #{term.year} (id=#{term.id})"
      else
        puts "  Warning: #{t[:season].to_s.capitalize} #{t[:year]} not found in DB — nothing to protect"
      end
      term
    end
    puts

    all_terms          = Term.all
    terms_to_wipe      = all_terms.reject { |t| protected_terms.map(&:id).include?(t.id) }
    terms_with_data    = terms_to_wipe.select do |t|
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
        FinalExam.where(term: term).delete_all
        FinalsSchedule.where(term: term).destroy_all
      end
    end

    puts
    if dry_run
      puts "Would delete: #{total_exams} FinalExam(s) and #{total_schedules} FinalsSchedule(s) across #{terms_with_data.size} term(s)."
      puts "Run without DRY_RUN=1 to apply."
    else
      puts "Deleted #{total_exams} FinalExam(s) and #{total_schedules} FinalsSchedule(s) across #{terms_with_data.size} term(s)."
    end
  end
end
