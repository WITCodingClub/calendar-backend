# frozen_string_literal: true

require "rails_helper"

RSpec.describe FinalsSchedules::Parser do
  let(:term) { create(:term) }
  let(:status) { instance_double(Process::Status, success?: true) }
  let(:pdf_text) { file_fixture("finals_schedules/spring_2026.txt").read }

  def stub_pdftotext(text, success: true, stderr: "")
    allow(status).to receive(:success?).and_return(success)
    allow(Open3).to receive(:capture3).with("pdftotext", "-layout", anything, "-").and_return([ text, stderr, status ])
  end

  def row(crn, time, room = "")
    format("%-15s%-33s%-8s%-31s%-30s%-21s%s", "ZQXA1000-01", "SAMPLE STUDIO", crn, "Doe, Jane",
           "Monday, May 4, 2026", time, room).rstrip
  end

  describe "argument validation" do
    it "requires PDF content" do
      expect { described_class.call(pdf_content: "", term: term) }
        .to raise_error(ArgumentError, "PDF content is required")
    end

    it "requires a Term" do
      expect { described_class.call(pdf_content: "x", term: nil) }
        .to raise_error(ArgumentError, "Term is required")
    end

    it "requires a string" do
      expect { described_class.call(pdf_content: [ 1 ], term: term) }
        .to raise_error(ArgumentError, "PDF content must be a string")
    end
  end

  describe "PDF text extraction" do
    it "raises with pdftotext's error when extraction fails" do
      stub_pdftotext("", success: false, stderr: "bad pdf")

      expect { described_class.call(pdf_content: "%PDF", term: term) }
        .to raise_error(RuntimeError, /Failed to extract text from PDF: bad pdf/)
    end

    it "uses a default message when stderr is empty" do
      stub_pdftotext("", success: false)

      expect { described_class.call(pdf_content: "%PDF", term: term) }
        .to raise_error(RuntimeError, /Unknown error/)
    end

    it "says pdftotext is missing when the binary is not installed" do
      allow(Open3).to receive(:capture3).with("pdftotext", "-layout", anything, "-")
        .and_raise(Errno::ENOENT, "pdftotext")

      expect { described_class.call(pdf_content: "%PDF", term: term) }
        .to raise_error(RuntimeError, /pdftotext is not installed/)
    end
  end

  describe "#call" do
    let!(:building) { create(:building, abbreviation: "ZQXB", name: "Sample Hall") }

    before { stub_pdftotext(pdf_text) }

    it "creates exams, links courses, and counts orphans" do
      course = create(:course, term: term, crn: 10_061)

      result = described_class.call(pdf_content: "%PDF", term: term)

      expect(result).to include(total: 2, created: 2, updated: 0, unchanged: 0, linked: 1, orphan: 1, errors: [], stale_crns: [])
      exam = FinalExam.find_by!(crn: 10_061, term: term)
      expect(exam).to have_attributes(
        course: course, exam_date: Date.new(2026, 4, 10), start_time: 1015, end_time: 1215,
        location: "ZQXB 205", combined_crns: [ 10_061 ]
      )
    end

    it "lists each new exam in the changes" do
      result = described_class.call(pdf_content: "%PDF", term: term)

      expect(result[:changes]).to contain_exactly(
        include(crn: 10_061, action: :create, changes: include("location" => [ nil, "ZQXB 205" ])),
        include(crn: 10_062, action: :create)
      )
    end

    it "creates missing rooms in known buildings once" do
      result = described_class.call(pdf_content: "%PDF", term: term)

      expect(result[:rooms_created]).to eq(2)
      expect(building.rooms.pluck(:number).map(&:to_i)).to contain_exactly(205, 419)
      expect(described_class.call(pdf_content: "%PDF", term: term)[:rooms_created]).to eq(0)
    end

    it "creates each room of a room list, with its letter" do
      stub_pdftotext(row("10001", "8:00 AM - 10:00 AM", "ZQXB 402A/B"))

      result = described_class.call(pdf_content: "%PDF", term: term)

      expect(result[:rooms_created]).to eq(2)
      expect(building.rooms.pluck(:number)).to contain_exactly("402A", "402B")
    end

    it "does not create a room that the catalog stores with leading zeros" do
      create(:room, building: building, number: "205")
      create(:room, building: building, number: "0419")

      result = described_class.call(pdf_content: "%PDF", term: term)

      expect(result[:rooms_created]).to eq(0)
      expect(building.rooms.pluck(:number)).to contain_exactly("205", "0419")
    end

    it "returns the parser warnings with the errors" do
      stub_pdftotext(format("%-15s%-8s%s", "ZQXA1000-01", "10001", "after lunch"))

      result = described_class.call(pdf_content: "%PDF", term: term)

      expect(result[:total]).to eq(0)
      expect(result[:errors]).to contain_exactly(a_string_including("Row has no exam date and time"))
    end

    it "counts only changed exams as updated on a second run and lists only real changes" do
      described_class.call(pdf_content: "%PDF", term: term)
      FinalExam.find_by!(crn: 10_062, term: term).update!(start_time: 800, end_time: 1000)

      result = described_class.call(pdf_content: "%PDF", term: term)

      expect(result).to include(created: 0, updated: 1, unchanged: 1)
      expect(result[:changes]).to contain_exactly(
        { crn: 10_062, action: :update, changes: { "start_time" => [ 800, 1500 ], "end_time" => [ 1000, 1700 ] } }
      )
      expect(FinalExam.where(term: term).count).to eq(2)
    end

    it "counts an exam that only gets a course link as unchanged" do
      described_class.call(pdf_content: "%PDF", term: term)
      create(:course, term: term, crn: 10_062)

      result = described_class.call(pdf_content: "%PDF", term: term)

      expect(result).to include(updated: 0, unchanged: 2, linked: 1)
      expect(result[:changes]).to be_empty
    end

    it "lists stored exams that the PDF no longer has, and keeps them" do
      create(:final_exam, term: term, crn: 10_099)

      result = described_class.call(pdf_content: "%PDF", term: term)

      expect(result[:stale_crns]).to eq([ 10_099 ])
      expect(FinalExam.exists?(term: term, crn: 10_099)).to be(true)
    end

    it "saves nothing in a dry run but reports the same result" do
      create(:final_exam, term: term, crn: 10_061, exam_date: Date.new(2026, 4, 1), start_time: 800, end_time: 1000)

      result = described_class.call(pdf_content: "%PDF", term: term, dry_run: true)

      expect(result).to include(total: 2, created: 1, updated: 1, unchanged: 0, rooms_created: 2)
      expect(result[:changes].map { |c| c[:crn] }).to contain_exactly(10_061, 10_062)
      expect(FinalExam.where(term: term).pluck(:crn)).to eq([ 10_061 ])
      expect(FinalExam.find_by!(crn: 10_061).start_time).to eq(800)
      expect(building.rooms).to be_empty
    end

    it "keeps going in a dry run after a database error on one entry" do
      allow(Rails.error).to receive(:report)
      allow(Course).to receive(:find_by).and_wrap_original do |original, **args|
        ActiveRecord::Base.connection.execute("SELECT 1/0") if args[:crn] == 10_061
        original.call(**args)
      end

      result = described_class.call(pdf_content: "%PDF", term: term, dry_run: true)

      expect(result[:errors]).to contain_exactly(a_string_including("Error processing CRN 10061"))
      expect(result).to include(created: 1)
    end

    it "skips locations in unknown buildings and blank locations" do
      stub_pdftotext([ row("10001", "8:00 AM - 10:00 AM", "NOPE 101"), row("10002", "8:00 AM - 10:00 AM") ].join("\n"))

      result = described_class.call(pdf_content: "%PDF", term: term)

      expect(result).to include(created: 2, rooms_created: 0)
    end

    it "records a validation error when the entry cannot be saved" do
      stub_pdftotext(row("10001", "10:00 AM - 8:00 AM"))

      result = described_class.call(pdf_content: "%PDF", term: term)

      expect(result[:created]).to eq(0)
      expect(result[:errors]).to include(a_string_matching(/Failed to save final exam for CRN 10001/))
    end

    it "reports unexpected errors per entry and keeps going" do
      allow(Rails.error).to receive(:report)
      allow(Course).to receive(:find_by).and_raise(StandardError, "boom")

      result = described_class.call(pdf_content: "%PDF", term: term)

      expect(result[:errors]).to include("Error processing CRN 10061: boom", "Error processing CRN 10062: boom")
      expect(Rails.error).to have_received(:report).with(instance_of(StandardError), handled: true, context: { crn: 10_061 })
    end

    it "handles an empty schedule" do
      stub_pdftotext("")

      expect(described_class.call(pdf_content: "%PDF", term: term)).to include(total: 0, created: 0)
    end
  end
end
