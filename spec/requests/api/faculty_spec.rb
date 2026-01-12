# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Faculty" do
  let(:user) { create(:user) }
  let(:jwt_token) { JsonWebTokenService.encode(user_id: user.id) }
  let(:headers) { { "Authorization" => "Bearer #{jwt_token}", "Content-Type" => "application/json" } }

  before do
    Flipper.enable(FlipperFlags::V1, user)
  end

  describe "GET /api/faculty/by_rmp" do
    context "when not authenticated" do
      it "returns unauthorized" do
        get "/api/faculty/by_rmp", params: { rmp_id: "test123" }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      context "with missing rmp_id parameter" do
        it "returns bad request" do
          get "/api/faculty/by_rmp", headers: headers

          expect(response).to have_http_status(:bad_request)
          expect(response.parsed_body["error"]).to eq("rmp_id parameter is required")
        end

        it "returns bad request for blank rmp_id" do
          get "/api/faculty/by_rmp", params: { rmp_id: "" }, headers: headers

          expect(response).to have_http_status(:bad_request)
          expect(response.parsed_body["error"]).to eq("rmp_id parameter is required")
        end
      end

      context "when faculty not found" do
        it "returns not found" do
          get "/api/faculty/by_rmp", params: { rmp_id: "nonexistent123" }, headers: headers

          expect(response).to have_http_status(:not_found)
          expect(response.parsed_body["error"]).to eq("Faculty not found")
        end
      end

      context "when faculty exists" do
        let(:faculty) do
          create(:faculty,
                 first_name: "John",
                 last_name: "Doe",
                 email: "john.doe@example.edu",
                 rmp_id: "existing_rmp_123",
                 rmp_raw_data: {
                   "all_ratings" => [
                     { "comment" => "Great teacher!", "clarityRating" => 5 }
                   ]
                 })
        end

        it "returns faculty info" do
          get "/api/faculty/by_rmp", params: { rmp_id: faculty.rmp_id }, headers: headers

          expect(response).to have_http_status(:ok)

          json = response.parsed_body
          expect(json["faculty_name"]).to eq(faculty.full_name)
          expect(json["email"]).to eq("john.doe@example.edu")
          expect(json["rmp_id"]).to eq("existing_rmp_123")
        end

        it "returns rmp ratings from raw data" do
          get "/api/faculty/by_rmp", params: { rmp_id: faculty.rmp_id }, headers: headers

          json = response.parsed_body
          expect(json["rmp_ratings"]).to be_an(Array)
          expect(json["rmp_ratings"].first["comment"]).to eq("Great teacher!")
        end

        context "with rating distribution" do
          before do
            create(:rating_distribution,
                   faculty: faculty,
                   avg_rating: 4.5,
                   avg_difficulty: 3.0,
                   num_ratings: 25,
                   would_take_again_percent: 88.5)
          end

          it "returns stats from rating distribution" do
            get "/api/faculty/by_rmp", params: { rmp_id: faculty.rmp_id }, headers: headers

            json = response.parsed_body
            expect(json["avg_rating"].to_f).to eq(4.5)
            expect(json["avg_difficulty"].to_f).to eq(3.0)
            expect(json["num_ratings"]).to eq(25)
            expect(json["would_take_again_percent"].to_f).to eq(88.5)
          end
        end

        context "without rating distribution" do
          it "returns nil stats" do
            get "/api/faculty/by_rmp", params: { rmp_id: faculty.rmp_id }, headers: headers

            json = response.parsed_body
            expect(json["avg_rating"]).to be_nil
            expect(json["avg_difficulty"]).to be_nil
            expect(json["num_ratings"]).to be_nil
            expect(json["would_take_again_percent"]).to be_nil
          end
        end
      end
    end

    context "when feature flag is disabled" do
      before do
        Flipper.disable(FlipperFlags::V1, user)
      end

      it "returns forbidden" do
        faculty = create(:faculty, rmp_id: "test123")
        get "/api/faculty/by_rmp", params: { rmp_id: faculty.rmp_id }, headers: headers

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
