# frozen_string_literal: true

require "rails_helper"

RSpec.describe FinalsSchedules::Parser do
  let(:term) { create(:term) }
  let(:status) { instance_double(Process::Status, success?: true) }
  let(:pdf_text) { file_fixture("finals_schedules/spring_2026.txt").read }

  def stub_pdftotext(text, success: true, stderr: "")
    allow(status).to receive(:success?).and_return(success)
    allow(Open3).to receive(:capture3).with("pdftotext", anything, "-").and_return([ text, stderr, status ])
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
  end

  describe "#call" do
    let!(:building) { create(:building, abbreviation: "ZQXB", name: "Sample Hall") }

    before { stub_pdftotext(pdf_text) }

    it "creates exams, links courses, and counts orphans" do
      course = create(:course, term: term, crn: 10_001)

      result = described_class.call(pdf_content: "%PDF", term: term)

      expect(result).to include(total: 2, created: 2, updated: 0, linked: 1, orphan: 1, errors: [])
      exam = FinalExam.find_by!(crn: 10_001, term: term)
      expect(exam).to have_attributes(
        course: course, exam_date: Date.new(2026, 5, 4), start_time: 800, end_time: 1000,
        location: "ZQXB 101", combined_crns: [ 10_001 ]
      )
    end

    it "creates missing rooms in known buildings once" do
      result = described_class.call(pdf_content: "%PDF", term: term)

      expect(result[:rooms_created]).to eq(2)
      expect(building.rooms.pluck(:number).map(&:to_i)).to contain_exactly(101, 102)
      expect(described_class.call(pdf_content: "%PDF", term: term)[:rooms_created]).to eq(0)
    end

    it "updates existing exams on a second run" do
      described_class.call(pdf_content: "%PDF", term: term)

      result = described_class.call(pdf_content: "%PDF", term: term)

      expect(result).to include(created: 0, updated: 2)
      expect(FinalExam.where(term: term).count).to eq(2)
    end

    it "skips locations in unknown buildings and blank locations" do
      stub_pdftotext("CRN\n10001\nEXAM-DATE\nMonday, May 4, 2026\nEXAM-TIME-OF-DAY\n8:00 AM - 10:00 AM\n" \
                     "EXAM-ROOM\nNOPE 101\n")

      result = described_class.call(pdf_content: "%PDF", term: term)

      expect(result).to include(created: 1, rooms_created: 0)
    end

    it "records a validation error when the entry cannot be saved" do
      stub_pdftotext("CRN\n10001\nEXAM-DATE\nMonday, May 4, 2026\n")

      result = described_class.call(pdf_content: "%PDF", term: term)

      expect(result[:created]).to eq(0)
      expect(result[:errors].first).to match(/Failed to save final exam for CRN 10001/)
    end

    it "reports unexpected errors per entry and keeps going" do
      allow(Rails.error).to receive(:report)
      allow(Course).to receive(:find_by).and_raise(StandardError, "boom")

      result = described_class.call(pdf_content: "%PDF", term: term)

      expect(result[:errors]).to include("Error processing CRN 10001: boom")
      expect(Rails.error).to have_received(:report).with(instance_of(StandardError), handled: true, context: { crn: 10_001 }).at_least(:once)
    end

    it "handles an empty schedule" do
      stub_pdftotext("")
      allow(Rails.logger).to receive(:warn)

      expect(described_class.call(pdf_content: "%PDF", term: term)).to include(total: 0, created: 0)
    end
  end

  describe "format detection" do
    it "picks the Fall 2025 parser for COMBINED CRNs text" do
      stub_pdftotext(file_fixture("finals_schedules/fall_2025.txt").read)

      expect(described_class.call(pdf_content: "%PDF", term: term)).to include(total: 3, created: 3)
    end

    it "picks the SpringFall parser for FINAL DAY text" do
      stub_pdftotext(file_fixture("finals_schedules/spring_fall.txt").read)

      expect(described_class.call(pdf_content: "%PDF", term: term)).to include(total: 3)
    end

    it "falls back to the first parser with the most entries for unknown text" do
      stub_pdftotext(file_fixture("finals_schedules/unknown.txt").read)
      allow(Rails.logger).to receive(:warn)

      result = described_class.call(pdf_content: "%PDF", term: term)

      expect(result).to include(total: 1, created: 1)
      expect(Rails.logger).to have_received(:warn).with(/Unknown finals PDF format; falling back to .*Fall2025Parser \(1 entries\)/)
    end
  end
end
