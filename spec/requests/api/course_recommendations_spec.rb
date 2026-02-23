# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::CourseRecommendations" do
  let(:user) { create(:user) }
  let(:jwt_token) { JsonWebTokenService.encode(user_id: user.id) }
  let(:headers) { { "Authorization" => "Bearer #{jwt_token}", "Content-Type" => "application/json" } }

  before { Flipper.enable(FlipperFlags::V1, user) }

  describe "GET /api/users/me/course_recommendations" do
    let(:term) { create(:term) }

    it "requires authentication" do
      get "/api/users/me/course_recommendations?term_uid=#{term.uid}"
      expect(response).to have_http_status(:unauthorized)
    end

    it "requires term_uid" do
      get "/api/users/me/course_recommendations", headers: headers
      expect(response).to have_http_status(:bad_request)
    end

    it "returns 404 for unknown term" do
      get "/api/users/me/course_recommendations?term_uid=INVALID", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "returns recommendations for valid term" do
      get "/api/users/me/course_recommendations?term_uid=#{term.uid}", headers: headers
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to have_key("term")
      expect(json).to have_key("recommendations")
      expect(json).to have_key("total")
    end

    it "returns empty recommendations when no courses exist" do
      get "/api/users/me/course_recommendations?term_uid=#{term.uid}", headers: headers
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["recommendations"]).to be_empty
      expect(json["total"]).to eq(0)
    end

    context "with courses in the term" do
      let!(:course) { create(:course, term: term, crn: 55555, credit_hours: 3, subject: "COMP", course_number: 2000) }

      it "returns course recommendations" do
        get "/api/users/me/course_recommendations?term_uid=#{term.uid}", headers: headers
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["total"]).to eq(1)

        rec = json["recommendations"].first
        expect(rec["course"]["crn"]).to eq(55555)
        expect(rec["course"]["subject"]).to eq("COMP")
        expect(rec["course"]["course_number"]).to eq(2000)
        expect(rec["course"]["credits"]).to eq(3)
        expect(rec).to have_key("priority")
        expect(rec).to have_key("prerequisite_status")
        expect(rec).to have_key("schedule_conflicts")
      end
    end

    context "excluding planned courses" do
      let!(:planned_course) { create(:course, term: term, subject: "COMP", course_number: 1000, crn: 11111) }
      let!(:available_course) { create(:course, term: term, subject: "COMP", course_number: 2000, crn: 22222) }

      before do
        create(:course_plan, user: user, term: term, course: planned_course,
                             planned_subject: "COMP", planned_course_number: 1000,
                             planned_crn: 11111, status: "planned")
      end

      it "does not recommend already-planned courses" do
        get "/api/users/me/course_recommendations?term_uid=#{term.uid}", headers: headers
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        crns = json["recommendations"].map { |r| r["course"]["crn"] }
        expect(crns).not_to include(11111)
        expect(crns).to include(22222)
      end
    end
  end
end
