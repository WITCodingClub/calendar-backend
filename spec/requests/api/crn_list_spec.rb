# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::CrnList" do
  let(:user) { create(:user) }
  let(:jwt_token) { JsonWebTokenService.encode(user_id: user.id) }
  let(:headers) { { "Authorization" => "Bearer #{jwt_token}", "Content-Type" => "application/json" } }

  before { Flipper.enable(FlipperFlags::V1, user) }

  describe "GET /api/users/me/crn_list" do
    let(:term) { create(:term) }

    it "requires authentication" do
      get "/api/users/me/crn_list?term_uid=#{term.uid}"
      expect(response).to have_http_status(:unauthorized)
    end

    it "requires term_uid" do
      get "/api/users/me/crn_list", headers: headers
      expect(response).to have_http_status(:bad_request)
    end

    it "returns 404 for unknown term" do
      get "/api/users/me/crn_list?term_uid=INVALID", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "returns crn list for valid term" do
      get "/api/users/me/crn_list?term_uid=#{term.uid}", headers: headers
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to have_key("courses")
      expect(json).to have_key("summary")
      expect(json).to have_key("term")
    end

    it "returns empty courses when no plans exist" do
      get "/api/users/me/crn_list?term_uid=#{term.uid}", headers: headers
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["courses"]).to be_empty
      expect(json["summary"]["total_planned"]).to eq(0)
    end

    context "with planned courses" do
      let(:course) { create(:course, term: term, crn: 55555, credit_hours: 3) }

      before do
        create(:course_plan, user: user, term: term, course: course,
               planned_subject: course.subject,
               planned_course_number: course.course_number,
               planned_crn: course.crn)
      end

      it "returns planned course in the list" do
        get "/api/users/me/crn_list?term_uid=#{term.uid}", headers: headers
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["courses"].size).to eq(1)
        expect(json["courses"].first["crn"]).to eq(55555)
        expect(json["summary"]["crn_list"]).to include("55555")
        expect(json["summary"]["total_credits"]).to eq(3)
      end
    end
  end

  describe "POST /api/users/me/crn_list/courses" do
    let(:term) { create(:term) }
    let(:course) { create(:course, term: term, crn: 99999) }

    it "requires authentication" do
      post "/api/users/me/crn_list/courses",
           params: { term_uid: term.uid, crn: course.crn,
                     subject: course.subject,
                     course_number: course.course_number
}.to_json,
           headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "adds a course to the plan by CRN" do
      post "/api/users/me/crn_list/courses",
           params: { term_uid: term.uid, crn: course.crn,
                     subject: course.subject,
                     course_number: course.course_number
}.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      json = response.parsed_body
      expect(json).to have_key("plan_id")
      expect(json["message"]).to eq("Course added to plan")
      expect(user.course_plans.count).to eq(1)
    end

    it "links the course record when CRN matches" do
      post "/api/users/me/crn_list/courses",
           params: { term_uid: term.uid, crn: course.crn,
                     subject: course.subject,
                     course_number: course.course_number
}.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      plan = user.course_plans.last
      expect(plan.course).to eq(course)
    end

    it "adds a course without a CRN (course not yet selected)" do
      post "/api/users/me/crn_list/courses",
           params: { term_uid: term.uid,
                     subject: "COMP",
                     course_number: 1500
}.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      expect(user.course_plans.last.planned_crn).to be_nil
    end

    it "returns 404 for unknown term" do
      post "/api/users/me/crn_list/courses",
           params: { term_uid: "INVALID", crn: 99999, subject: "COMP", course_number: 1000 }.to_json,
           headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/users/me/crn_list/courses/:id" do
    let(:term) { create(:term) }
    let!(:plan) { create(:course_plan, user: user, term: term) }

    it "requires authentication" do
      delete "/api/users/me/crn_list/courses/#{plan.id}"
      expect(response).to have_http_status(:unauthorized)
    end

    it "removes the course from the plan" do
      delete "/api/users/me/crn_list/courses/#{plan.id}", headers: headers
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["ok"]).to be true
      expect(user.course_plans.count).to eq(0)
    end

    it "returns 404 if plan not found" do
      delete "/api/users/me/crn_list/courses/99999", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "cannot delete another user's plan" do
      other_user = create(:user)
      Flipper.enable(FlipperFlags::V1, other_user)
      other_token = JsonWebTokenService.encode(user_id: other_user.id)
      other_headers = { "Authorization" => "Bearer #{other_token}", "Content-Type" => "application/json" }

      delete "/api/users/me/crn_list/courses/#{plan.id}", headers: other_headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
