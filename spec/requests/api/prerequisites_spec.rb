# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::Prerequisites", :openapi do
  let(:user) { create(:user) }
  let(:jwt_token) { JsonWebTokenService.encode(user_id: user.id) }
  let(:auth_headers) { { "Authorization" => "Bearer #{jwt_token}" } }
  let(:term) { create(:term) }
  let(:course) { create(:course, term: term, subject: "COMP", course_number: 2000) }
  let(:degree_requirement) { create(:degree_requirement) }

  before do
    Flipper.enable(FlipperFlags::V1, user)
  end

  describe "GET /api/courses/:id/prerequisites" do
    context "when the course has prerequisites" do
      before do
        create(:course_prerequisite,
               course: course,
               prerequisite_type: "prerequisite",
               prerequisite_rule: "COMP 1000",
               min_grade: "C",
               waivable: false)
        create(:course_prerequisite,
               course: course,
               prerequisite_type: "corequisite",
               prerequisite_rule: "MATH 2300",
               min_grade: nil,
               waivable: true)
      end

      it "returns 200 with list of prerequisites" do
        get "/api/courses/#{course.id}/prerequisites", headers: auth_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["prerequisites"]).to be_an(Array)
        expect(json["prerequisites"].length).to eq(2)
      end

      it "includes expected fields for each prerequisite" do
        get "/api/courses/#{course.id}/prerequisites", headers: auth_headers

        prereq = response.parsed_body["prerequisites"].find { |p| p["type"] == "prerequisite" }
        expect(prereq["type"]).to eq("prerequisite")
        expect(prereq["rule"]).to eq("COMP 1000")
        expect(prereq["min_grade"]).to eq("C")
        expect(prereq["waivable"]).to be false
      end

      it "includes corequisites" do
        get "/api/courses/#{course.id}/prerequisites", headers: auth_headers

        coreq = response.parsed_body["prerequisites"].find { |p| p["type"] == "corequisite" }
        expect(coreq["type"]).to eq("corequisite")
        expect(coreq["rule"]).to eq("MATH 2300")
        expect(coreq["waivable"]).to be true
      end
    end

    context "when the course has no prerequisites" do
      it "returns 200 with an empty array" do
        get "/api/courses/#{course.id}/prerequisites", headers: auth_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["prerequisites"]).to be_empty
      end
    end

    context "when looking up by public_id" do
      it "returns 200 using the course public_id" do
        get "/api/courses/#{course.public_id}/prerequisites", headers: auth_headers

        expect(response).to have_http_status(:ok)
      end
    end

    context "when the course does not exist" do
      it "returns 404" do
        get "/api/courses/999999/prerequisites", headers: auth_headers

        expect(response).to have_http_status(:not_found)
      end
    end

    context "without authentication" do
      it "returns 401" do
        get "/api/courses/#{course.id}/prerequisites"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /api/courses/:id/check_eligibility" do
    context "when the course has no prerequisites" do
      it "returns eligible: true" do
        post "/api/courses/#{course.id}/check_eligibility", headers: auth_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["eligible"]).to be true
        expect(json["requirements"]).to be_empty
      end
    end

    context "when the user has not completed the prerequisite" do
      before do
        create(:course_prerequisite,
               course: course,
               prerequisite_type: "prerequisite",
               prerequisite_rule: "COMP 1000")
      end

      it "returns eligible: false" do
        post "/api/courses/#{course.id}/check_eligibility", headers: auth_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["eligible"]).to be false
        expect(json["requirements"].first["met"]).to be false
      end
    end

    context "when the user has completed the prerequisite" do
      before do
        create(:course_prerequisite,
               course: course,
               prerequisite_type: "prerequisite",
               prerequisite_rule: "COMP 1000")
        create(:requirement_completion,
               user: user,
               degree_requirement: degree_requirement,
               subject: "COMP",
               course_number: 1000,
               in_progress: false)
      end

      it "returns eligible: true" do
        post "/api/courses/#{course.id}/check_eligibility", headers: auth_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["eligible"]).to be true
        expect(json["requirements"].first["met"]).to be true
      end
    end

    context "when the course does not exist" do
      it "returns 404" do
        post "/api/courses/999999/check_eligibility", headers: auth_headers

        expect(response).to have_http_status(:not_found)
      end
    end

    context "without authentication" do
      it "returns 401" do
        post "/api/courses/#{course.id}/check_eligibility"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
