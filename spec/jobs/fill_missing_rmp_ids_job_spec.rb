# frozen_string_literal: true

require "rails_helper"

RSpec.describe FillMissingRmpIdsJob do
  describe "queue assignment" do
    it "is assigned to the low queue" do
      expect(described_class.new.queue_name).to eq("low")
    end
  end

  describe "#perform" do
    before do
      # Prevent real sleeps in tests
      allow_any_instance_of(described_class).to receive(:sleep)
    end

    context "when all faculty with courses have RMP IDs" do
      before do
        faculty = create(:faculty, rmp_id: "existing-id")
        course = create(:course)
        course.faculties << faculty
      end

      it "returns without processing any faculty" do
        allow(UpdateFacultyRatingsJob).to receive(:perform_now)

        described_class.perform_now

        expect(UpdateFacultyRatingsJob).not_to have_received(:perform_now)
      end
    end

    context "when there are faculty with courses and missing RMP IDs" do
      let!(:faculty_without_rmp) do
        faculty = create(:faculty, rmp_id: nil)
        course = create(:course)
        course.faculties << faculty
        faculty
      end

      it "calls UpdateFacultyRatingsJob for each faculty without an RMP ID" do
        allow(UpdateFacultyRatingsJob).to receive(:perform_now)
        allow(faculty_without_rmp).to receive(:reload)

        described_class.perform_now

        expect(UpdateFacultyRatingsJob).to have_received(:perform_now).with(faculty_without_rmp.id)
      end

      context "when UpdateFacultyRatingsJob raises an error" do
        before do
          allow(UpdateFacultyRatingsJob).to receive(:perform_now).and_raise(StandardError.new("RMP timeout"))
        end

        it "rescues the error and continues processing remaining faculty" do
          expect { described_class.perform_now }.not_to raise_error
        end
      end
    end

    context "when faculty exist but have no courses" do
      before { create(:faculty, rmp_id: nil) }

      it "does not process faculty without courses" do
        allow(UpdateFacultyRatingsJob).to receive(:perform_now)

        described_class.perform_now

        expect(UpdateFacultyRatingsJob).not_to have_received(:perform_now)
      end
    end
  end
end
