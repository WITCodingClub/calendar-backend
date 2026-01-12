# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateFacultyRatingsJob do
  let(:service) { instance_double(RateMyProfessorService) }

  before do
    allow(RateMyProfessorService).to receive(:new).and_return(service)
  end

  describe "queue assignment" do
    it "is assigned to the low queue" do
      expect(described_class.new.queue_name).to eq("low")
    end
  end

  describe "#perform" do
    context "when faculty does not teach courses" do
      let(:faculty) { create(:faculty) }

      it "skips processing and logs" do
        expect(faculty.teaches_courses?).to be false

        allow(Rails.logger).to receive(:info)

        described_class.new.perform(faculty.id)

        expect(Rails.logger).to have_received(:info).with(include("no_courses"))
      end

      it "does not call RateMyProfessorService" do
        expect(service).not_to receive(:search_professors)
        expect(service).not_to receive(:get_teacher_details)

        described_class.new.perform(faculty.id)
      end
    end

    context "when faculty teaches courses but has no rmp_id" do
      let(:faculty) { create(:faculty, rmp_id: nil) }
      let(:course) { create(:course) }

      before do
        faculty.courses << course
      end

      context "when search finds a match" do
        let(:search_result) do
          {
            "data" => {
              "newSearch" => {
                "teachers" => {
                  "edges" => [
                    {
                      "node" => {
                        "id"        => "test_rmp_123",
                        "firstName" => faculty.first_name,
                        "lastName"  => faculty.last_name
                      }
                    }
                  ]
                }
              }
            }
          }
        end

        let(:teacher_details) do
          {
            "data" => {
              "node" => {
                "avgRating"             => 4.5,
                "avgDifficulty"         => 3.0,
                "numRatings"            => 10,
                "wouldTakeAgainPercent" => 85.0,
                "ratingsDistribution"   => {
                  "r1" => 0, "r2" => 1, "r3" => 2, "r4" => 3, "r5" => 4, "total" => 10
                },
                "teacherRatingTags"     => [],
                "relatedTeachers"       => []
              }
            }
          }
        end

        before do
          allow(service).to receive_messages(search_professors: search_result, get_teacher_details: teacher_details, get_all_ratings: [])
        end

        it "searches for the faculty and updates rmp_id" do
          described_class.new.perform(faculty.id)

          expect(faculty.reload.rmp_id).to eq("test_rmp_123")
        end

        it "fetches and stores ratings" do
          expect(service).to receive(:get_teacher_details).with("test_rmp_123")
          expect(service).to receive(:get_all_ratings).with("test_rmp_123")

          described_class.new.perform(faculty.id)
        end
      end

      context "when search finds no match" do
        let(:search_result) do
          { "data" => { "newSearch" => { "teachers" => { "edges" => [] } } } }
        end

        before do
          allow(service).to receive(:search_professors).and_return(search_result)
        end

        it "logs and skips" do
          allow(Rails.logger).to receive(:info)

          described_class.new.perform(faculty.id)

          expect(Rails.logger).to have_received(:info).with(include("no_rmp_id"))
        end

        it "does not fetch teacher details" do
          expect(service).not_to receive(:get_teacher_details)

          described_class.new.perform(faculty.id)
        end
      end
    end

    context "when faculty has rmp_id" do
      let(:faculty) { create(:faculty, rmp_id: "existing_rmp_id") }
      let(:course) { create(:course) }

      let(:teacher_details) do
        {
          "data" => {
            "node" => {
              "avgRating"             => 4.5,
              "avgDifficulty"         => 3.0,
              "numRatings"            => 2,
              "wouldTakeAgainPercent" => 100.0,
              "ratingsDistribution"   => {
                "r1" => 0, "r2" => 0, "r3" => 0, "r4" => 1, "r5" => 1, "total" => 2
              },
              "teacherRatingTags"     => [
                { "legacyId" => 1, "tagName" => "Helpful", "tagCount" => 5 }
              ],
              "relatedTeachers"       => [
                { "id" => "related_rmp_1", "firstName" => "Jane", "lastName" => "Doe", "avgRating" => 4.0 }
              ]
            }
          }
        }
      end

      let(:ratings_data) do
        [
          {
            "legacyId"            => 12345,
            "clarityRating"       => 5,
            "difficultyRating"    => 2,
            "helpfulRating"       => 5,
            "class"               => "CS 101",
            "comment"             => "Great professor!",
            "date"                => "2024-01-15",
            "grade"               => "A",
            "wouldTakeAgain"      => "Yes",
            "attendanceMandatory" => "No",
            "isForCredit"         => true,
            "isForOnlineClass"    => false,
            "ratingTags"          => "Helpful,Clear",
            "thumbsUpTotal"       => 10,
            "thumbsDownTotal"     => 1
          }
        ]
      end

      before do
        faculty.courses << course
        allow(service).to receive_messages(get_teacher_details: teacher_details, get_all_ratings: ratings_data)
      end

      it "does not search for faculty" do
        expect(service).not_to receive(:search_professors)

        described_class.new.perform(faculty.id)
      end

      it "fetches teacher details using existing rmp_id" do
        expect(service).to receive(:get_teacher_details).with("existing_rmp_id")

        described_class.new.perform(faculty.id)
      end

      it "stores rating distribution" do
        described_class.new.perform(faculty.id)

        distribution = faculty.reload.rating_distribution
        expect(distribution).to be_present
        expect(distribution.avg_rating).to eq(4.5)
        expect(distribution.avg_difficulty).to eq(3.0)
        expect(distribution.num_ratings).to eq(2)
        expect(distribution.r5).to eq(1)
      end

      it "stores teacher rating tags" do
        described_class.new.perform(faculty.id)

        tags = faculty.reload.teacher_rating_tags
        expect(tags.count).to eq(1)
        expect(tags.first.tag_name).to eq("Helpful")
        expect(tags.first.tag_count).to eq(5)
      end

      it "stores related professors" do
        described_class.new.perform(faculty.id)

        related = faculty.reload.related_professors
        expect(related.count).to eq(1)
        expect(related.first.first_name).to eq("Jane")
        expect(related.first.last_name).to eq("Doe")
        expect(related.first.rmp_id).to eq("related_rmp_1")
      end

      it "stores individual ratings" do
        described_class.new.perform(faculty.id)

        ratings = faculty.reload.rmp_ratings
        expect(ratings.count).to eq(1)

        rating = ratings.first
        expect(rating.clarity_rating).to eq(5)
        expect(rating.course_name).to eq("CS 101")
        expect(rating.comment).to eq("Great professor!")
        expect(rating.would_take_again).to be true
      end

      it "stores raw data" do
        described_class.new.perform(faculty.id)

        expect(faculty.reload.rmp_raw_data).to be_present
        expect(faculty.rmp_raw_data["metadata"]["total_ratings_fetched"]).to eq(1)
      end
    end

    context "when teacher details return nil node" do
      let(:faculty) { create(:faculty, rmp_id: "some_rmp_id") }
      let(:course) { create(:course) }

      before do
        faculty.courses << course
        allow(service).to receive(:get_teacher_details).and_return({ "data" => { "node" => nil } })
      end

      it "handles gracefully without creating records" do
        expect { described_class.new.perform(faculty.id) }.not_to raise_error
        expect(faculty.reload.rating_distribution).to be_nil
      end
    end
  end
end
