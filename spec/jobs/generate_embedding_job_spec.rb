# frozen_string_literal: true

require "rails_helper"

RSpec.describe GenerateEmbeddingJob do
  let(:service) { instance_double(EmbeddingService) }

  before do
    allow(EmbeddingService).to receive(:new).and_return(service)
  end

  describe "#perform" do
    context "with Course" do
      let(:course) { create(:course) }

      it "generates embedding for the record" do
        allow(service).to receive(:embed_record).and_return(true)

        described_class.perform_now("Course", course.id)

        expect(service).to have_received(:embed_record).with(course)
      end

      it "handles non-existent record gracefully" do
        expect {
          described_class.perform_now("Course", 999_999)
        }.not_to raise_error
      end
    end

    context "with Faculty" do
      let(:faculty) { create(:faculty) }

      it "generates embedding for the record" do
        allow(service).to receive(:embed_record).and_return(true)

        described_class.perform_now("Faculty", faculty.id)

        expect(service).to have_received(:embed_record).with(faculty)
      end
    end

    context "with RmpRating" do
      let(:faculty) { create(:faculty) }
      let(:rmp_rating) { create(:rmp_rating, faculty: faculty) }

      it "generates embedding for the record" do
        allow(service).to receive(:embed_record).and_return(true)

        described_class.perform_now("RmpRating", rmp_rating.id)

        expect(service).to have_received(:embed_record).with(rmp_rating)
      end
    end
  end

  describe "error handling" do
    let(:course) { create(:course) }

    it "logs warning when record is not found" do
      allow(Rails.logger).to receive(:warn)

      described_class.perform_now("Course", 999_999)

      expect(Rails.logger).to have_received(:warn).with(/Record not found/)
    end
  end
end
