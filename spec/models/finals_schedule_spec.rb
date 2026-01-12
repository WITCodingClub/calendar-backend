# frozen_string_literal: true

# == Schema Information
#
# Table name: finals_schedules
# Database name: primary
#
#  id             :bigint           not null, primary key
#  error_message  :text
#  processed_at   :datetime
#  stats          :jsonb
#  status         :integer          default("pending"), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  term_id        :bigint           not null
#  uploaded_by_id :bigint           not null
#
# Indexes
#
#  index_finals_schedules_on_term_id                 (term_id)
#  index_finals_schedules_on_term_id_and_created_at  (term_id,created_at)
#  index_finals_schedules_on_uploaded_by_id          (uploaded_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#  fk_rails_...  (uploaded_by_id => users.id)
#
require "rails_helper"

RSpec.describe FinalsSchedule do
  describe "associations" do
    it { is_expected.to belong_to(:term) }
    it { is_expected.to belong_to(:uploaded_by).class_name("User") }
  end

  describe "validations" do
    it "validates presence of pdf_file" do
      schedule = build(:finals_schedule)
      schedule.pdf_file.purge
      expect(schedule).not_to be_valid
      expect(schedule.errors[:pdf_file]).to include("can't be blank")
    end

    it "validates pdf_file content type" do
      schedule = build(:finals_schedule)
      schedule.pdf_file.attach(
        io: StringIO.new("not a pdf"),
        filename: "test.txt",
        content_type: "text/plain"
      )
      expect(schedule).not_to be_valid
      expect(schedule.errors[:pdf_file]).to include("must be a PDF")
    end

    it "accepts valid PDF file" do
      schedule = build(:finals_schedule)
      expect(schedule).to be_valid
    end
  end

  describe "enum status" do
    it "defines correct status values" do
      expect(described_class.statuses).to eq({
                                               "pending"    => 0,
                                               "processing" => 1,
                                               "completed"  => 2,
                                               "failed"     => 3
                                             })
    end

    it "defaults to pending" do
      schedule = described_class.new
      expect(schedule.status).to eq("pending")
    end
  end

  describe "scopes" do
    describe ".recent" do
      it "orders by created_at descending" do
        old = create(:finals_schedule, created_at: 2.days.ago)
        new = create(:finals_schedule, created_at: 1.day.ago)
        expect(described_class.recent).to eq([new, old])
      end
    end

    describe ".for_term" do
      it "filters by term" do
        term1 = create(:term)
        term2 = create(:term)
        schedule1 = create(:finals_schedule, term: term1)
        create(:finals_schedule, term: term2)

        expect(described_class.for_term(term1)).to eq([schedule1])
      end
    end
  end

  describe "#process!" do
    let(:schedule) { create(:finals_schedule) }
    let(:mock_result) do
      {
        total: 10,
        created: 8,
        updated: 1,
        linked: 7,
        orphan: 2,
        rooms_created: 0,
        errors: []
      }
    end

    before do
      allow(FinalsScheduleParserService).to receive(:call).and_return(mock_result)
    end

    it "updates status to processing" do
      expect { schedule.process! }.to change { schedule.reload.status }.from("pending").to("completed")
    end

    it "calls parser service with pdf content" do
      schedule.process!
      expect(FinalsScheduleParserService).to have_received(:call).with(
        pdf_content: schedule.pdf_file.download,
        term: schedule.term
      )
    end

    it "updates stats on success" do
      schedule.process!
      expect(schedule.reload.stats).to eq({
                                            "total"         => 10,
                                            "created"       => 8,
                                            "updated"       => 1,
                                            "linked"        => 7,
                                            "orphan"        => 2,
                                            "rooms_created" => 0
                                          })
    end

    it "sets processed_at on success" do
      freeze_time do
        schedule.process!
        expect(schedule.reload.processed_at).to eq(Time.current)
      end
    end

    it "stores error messages from parsing" do
      allow(FinalsScheduleParserService).to receive(:call).and_return(
        mock_result.merge(errors: ["Error 1", "Error 2"])
      )
      schedule.process!
      expect(schedule.reload.error_message).to eq("Error 1\nError 2")
    end

    context "when parsing fails" do
      before do
        allow(FinalsScheduleParserService).to receive(:call)
          .and_raise(StandardError, "PDF parsing failed")
      end

      it "sets status to failed" do
        expect { schedule.process! }.to raise_error(StandardError)
        expect(schedule.reload.status).to eq("failed")
      end

      it "stores error message" do
        expect { schedule.process! }.to raise_error(StandardError)
        expect(schedule.reload.error_message).to eq("PDF parsing failed")
      end

      it "sets processed_at" do
        freeze_time do
          expect { schedule.process! }.to raise_error(StandardError)
          expect(schedule.reload.processed_at).to eq(Time.current)
        end
      end
    end
  end

  describe "ActiveStorage attachment" do
    it "can attach a PDF file" do
      schedule = create(:finals_schedule)
      expect(schedule.pdf_file).to be_attached
    end

    it "stores the correct content type" do
      schedule = create(:finals_schedule)
      expect(schedule.pdf_file.content_type).to eq("application/pdf")
    end
  end
end
