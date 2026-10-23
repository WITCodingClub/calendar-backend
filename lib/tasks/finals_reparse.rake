# frozen_string_literal: true

namespace :finals do
  # One-time fix for finals that the old per-format parsers saved with wrong
  # dates, times, or rooms, or did not save. Remove this task when it has run
  # on production. See docs/finals-schedules.md.
  desc "Parse the latest finals PDF of each term again with FinalsSchedules::TableParser. " \
       "Dry run by default; pass APPLY=1 to save. TERM_UID=<uid> limits it to one term."
  task reparse: :environment do
    apply = ENV["APPLY"] == "1"
    terms = ENV["TERM_UID"].present? ? Term.where(uid: ENV["TERM_UID"].to_i) : Term.order(:uid)
    current_and_future = Term.current_and_future.pluck(:id)

    puts apply ? "Saving changes." : "DRY RUN: no changes are saved. Pass APPLY=1 to save."

    terms.each do |term|
      schedule = FinalsSchedule.for_term(term).completed.recent.find { |s| s.pdf_file.attached? }
      next unless schedule

      # A newer upload in the queue would race with this run, and the older
      # PDF could win.
      if FinalsSchedule.for_term(term).where(status: %i[pending processing]).where("created_at > ?", schedule.created_at).exists?
        puts
        puts "#{term.name} (#{term.uid}): skipped, a newer upload is still processing"
        next
      end

      result = FinalsSchedules::Parser.call(pdf_content: schedule.pdf_file.download, term: term, dry_run: !apply)

      puts
      puts "#{term.name} (#{term.uid}), upload #{schedule.id} of #{schedule.created_at.to_date}: " \
           "#{result[:total]} exams, #{result[:created]} new, #{result[:changes].count { |c| c[:action] == :update }} changed"

      result[:changes].each do |change|
        if change[:action] == :create
          puts "  + #{change[:crn]}"
        else
          details = change[:changes].map { |attr, (from, to)| "#{attr} #{from.inspect} -> #{to.inspect}" }
          puts "  ~ #{change[:crn]}: #{details.join('; ')}"
        end
      end
      puts "  Not in the PDF (kept): #{result[:stale_crns].join(', ')}" if result[:stale_crns].any?
      result[:errors].each { |error| puts "  ! #{error}" }

      next unless apply

      schedule.update!(
        processed_at:  Time.current,
        stats:         result.slice(:total, :created, :updated, :linked, :orphan, :rooms_created),
        error_message: result[:errors].presence&.join("\n")
      )
      # Past terms get no calendar sync: their events are over. Between terms
      # there is no current term, so an exam still to come also counts.
      upcoming = current_and_future.include?(term.id) || FinalExam.where(term: term, exam_date: Date.current..).exists?
      schedule.trigger_calendar_resyncs_for_term if upcoming && result[:changes].any?
    end
  end

  desc "Parse every PDF in DIR with FinalsSchedules::TableParser and print counts and warnings. " \
       "Use it to check a new PDF format before an upload."
  task check_corpus: :environment do
    dir = ENV.fetch("DIR") { abort "Pass DIR=<folder of finals PDFs>" }

    Dir[File.join(dir, "*.pdf")].sort.each do |path|
      parser  = FinalsSchedules::TableParser.new
      entries = parser.parse(FinalsSchedules::PdfText.extract(File.binread(path)))

      puts "#{File.basename(path)}: #{entries.size} CRNs, " \
           "#{entries.count { |e| e[:combined_crns].size > 1 }} combined, " \
           "#{entries.count { |e| e[:location].nil? }} with no room, #{parser.warnings.size} warnings"
      parser.warnings.each { |warning| puts "  ! #{warning}" }
    end
  end
end
