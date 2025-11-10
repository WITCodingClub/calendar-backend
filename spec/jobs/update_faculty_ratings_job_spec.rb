# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateFacultyRatingsJob do
  describe "queue assignment" do
    it "is assigned to the low queue" do
      expect(described_class.new.queue_name).to eq("low")
    end
  end

  describe "#perform" do
    let(:faculty) { create(:faculty) }
    let(:service) { instance_double(RateMyProfessorService) }

    before do
      allow(RateMyProfessorService).to receive(:new).and_return(service)
    end

    context "when ratings were updated recently" do
      before do
        create(:rating_distribution, faculty: faculty, updated_at: 3.days.ago)
      end

      it "skips the job and logs a message" do
        expect(Rails.logger).to receive(:info).with(/Skipping.*ratings updated recently/)
        expect(service).not_to receive(:search_professors)
        expect(service).not_to receive(:get_teacher_details)

        described_class.perform_now(faculty.id)
      end

      it "does not fetch new ratings" do
        expect(service).not_to receive(:get_all_ratings)
        described_class.perform_now(faculty.id)
      end
    end

    context "when ratings were updated more than a week ago" do
      before do
        create(:rating_distribution, faculty: faculty, updated_at: 8.days.ago)
        faculty.update!(rmp_id: "12345")
        
        allow(service).to receive(:get_teacher_details).and_return({
          "data" => {
            "node" => {
              "avgRating" => 4.5,
              "avgDifficulty" => 3.0,
              "numRatings" => 10,
              "wouldTakeAgainPercent" => 80,
              "ratingsDistribution" => {
                "r1" => 1, "r2" => 2, "r3" => 3, "r4" => 4, "r5" => 5, "total" => 15
              },
              "teacherRatingTags" => [],
              "relatedTeachers" => []
            }
          }
        })
        allow(service).to receive(:get_all_ratings).and_return([])
      end

      it "fetches new ratings" do
        expect(service).to receive(:get_teacher_details).with(faculty.rmp_id)
        expect(service).to receive(:get_all_ratings).with(faculty.rmp_id)

        described_class.perform_now(faculty.id)
      end
    end

    context "when faculty has no rating_distribution" do
      before do
        faculty.update!(rmp_id: "12345")
        
        allow(service).to receive(:get_teacher_details).and_return({
          "data" => {
            "node" => {
              "avgRating" => 4.5,
              "avgDifficulty" => 3.0,
              "numRatings" => 10,
              "wouldTakeAgainPercent" => 80,
              "ratingsDistribution" => {
                "r1" => 1, "r2" => 2, "r3" => 3, "r4" => 4, "r5" => 5, "total" => 15
              },
              "teacherRatingTags" => [],
              "relatedTeachers" => []
            }
          }
        })
        allow(service).to receive(:get_all_ratings).and_return([])
      end

      it "fetches ratings" do
        expect(service).to receive(:get_teacher_details).with(faculty.rmp_id)
        expect(service).to receive(:get_all_ratings).with(faculty.rmp_id)

        described_class.perform_now(faculty.id)
      end
    end

    context "when faculty has no rmp_id" do
      before do
        faculty.update!(rmp_id: nil)
      end

      it "attempts to search and link the faculty" do
        allow(service).to receive(:search_professors).and_return({
          "data" => { "newSearch" => { "teachers" => { "edges" => [] } } }
        })

        expect(service).to receive(:search_professors).with(faculty.full_name, count: 10)
        described_class.perform_now(faculty.id)
      end
    end
  end
end
