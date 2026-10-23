# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "finals rake tasks" do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  let(:status) { instance_double(Process::Status, success?: true) }
  let(:pdf_text) { file_fixture("finals_schedules/spring_2026.txt").read }

  before do
    allow(Open3).to receive(:capture3).with("pdftotext", "-layout", anything, "-").and_return([ pdf_text, "", status ])
  end

  around do |example|
    keys  = %w[APPLY TERM_UID DIR]
    saved = keys.to_h { |key| [ key, ENV.fetch(key, nil) ] }
    keys.each { |key| ENV.delete(key) }
    example.run
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def run_task(name, env = {})
    env.each { |key, value| ENV[key] = value }
    task = Rake::Task[name]
    task.reenable
    original = $stdout
    $stdout = StringIO.new
    task.invoke
    $stdout.string
  ensure
    $stdout = original
  end

  def schedule_for(term, status: :completed)
    create(:finals_schedule, term: term, status: status).tap do |schedule|
      schedule.pdf_file.attach(io: StringIO.new("%PDF-1.4"), filename: "finals.pdf", content_type: "application/pdf")
    end
  end

  describe "finals:reparse" do
    let(:past) { create(:term, year: 2025, season: :spring) }

    before do
      schedule_for(past)
      create(:final_exam, term: past, crn: 10_061, exam_date: Date.new(2026, 4, 1), start_time: 800, end_time: 1000)
      create(:final_exam, term: past, crn: 10_099, exam_date: Date.new(2026, 4, 9))
    end

    it "prints the changes and saves nothing in a dry run" do
      output = run_task("finals:reparse")

      expect(output).to include("DRY RUN", "+ 10062", "~ 10061: exam_date", "Not in the PDF (kept): 10099")
      expect(FinalExam.where(term: past).pluck(:crn)).to contain_exactly(10_061, 10_099)
      expect(FinalExam.find_by!(term: past, crn: 10_061).start_time).to eq(800)
    end

    it "saves the changes with APPLY=1 and does not sync a past term" do
      allow(Term).to receive(:current_and_future).and_return(Term.none)
      synced = []
      allow_any_instance_of(FinalsSchedule).to receive(:trigger_calendar_resyncs_for_term) { |schedule| synced << schedule.term_id } # rubocop:disable RSpec/AnyInstance

      run_task("finals:reparse", "APPLY" => "1")

      expect(synced).to eq([])

      expect(FinalExam.find_by!(term: past, crn: 10_061)).to have_attributes(start_time: 1015, exam_date: Date.new(2026, 4, 10))
      expect(FinalExam.exists?(term: past, crn: 10_062)).to be(true)
      expect(FinalExam.exists?(term: past, crn: 10_099)).to be(true)
      expect(FinalsSchedule.find_by!(term: past).stats).to include("total" => 2, "created" => 1)
    end

    it "syncs calendars for a current or future term with changes" do
      future = create(:term, year: 2031, season: :fall)
      schedule_for(future)
      allow(Term).to receive(:current_and_future).and_return(Term.where(id: future.id))
      synced = []
      allow_any_instance_of(FinalsSchedule).to receive(:trigger_calendar_resyncs_for_term) { |schedule| synced << schedule.term_id } # rubocop:disable RSpec/AnyInstance

      run_task("finals:reparse", "APPLY" => "1")

      expect(synced).to eq([ future.id ])
    end

    it "syncs calendars between terms when the term still has an exam to come" do
      allow(Term).to receive(:current_and_future).and_return(Term.none)
      create(:final_exam, term: past, exam_date: Date.current + 30)
      synced = []
      allow_any_instance_of(FinalsSchedule).to receive(:trigger_calendar_resyncs_for_term) { |schedule| synced << schedule.term_id } # rubocop:disable RSpec/AnyInstance

      run_task("finals:reparse", "APPLY" => "1")

      expect(synced).to eq([ past.id ])
    end

    it "skips a term with a newer upload still processing" do
      create(:finals_schedule, term: past, status: :pending)

      output = run_task("finals:reparse", "APPLY" => "1")

      expect(output).to include("skipped, a newer upload is still processing")
      expect(FinalExam.find_by!(term: past, crn: 10_061).start_time).to eq(800)
    end

    it "limits the run to TERM_UID and uses only completed uploads with a PDF" do
      other = create(:term, year: 2025, season: :fall)
      schedule_for(other, status: :failed)

      output = run_task("finals:reparse", "TERM_UID" => other.uid.to_s)

      expect(output).not_to include(past.name)
      expect(output).not_to include(other.name)
    end
  end

  describe "finals:check_corpus" do
    it "prints counts and warnings for each PDF in DIR" do
      Dir.mktmpdir do |dir|
        File.binwrite(File.join(dir, "spring.pdf"), "%PDF-1.4")
        allow(Open3).to receive(:capture3).with("pdftotext", "-layout", anything, "-")
          .and_return([ "#{pdf_text}ZQXA1000-01   10001   after lunch\n", "", status ])

        output = run_task("finals:check_corpus", "DIR" => dir)

        expect(output).to include("spring.pdf: 2 CRNs, 0 combined, 0 with no room, 1 warnings", "Row has no exam date and time")
      end
    end
  end
end
