# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::CoursePlans" do
  let(:user) { create(:user) }
  let(:jwt_token) { JsonWebTokenService.encode(user_id: user.id) }
  let(:headers) { { "Authorization" => "Bearer #{jwt_token}", "Content-Type" => "application/json" } }

  before { Flipper.enable(FlipperFlags::V1, user) }

  describe "GET /api/users/me/course_plans" do
    let(:term) { create(:term) }

    it "requires authentication" do
      get "/api/users/me/course_plans"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns empty array when no plans exist" do
      get "/api/users/me/course_plans", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
    end

    context "with plans" do
      let!(:plan) { create(:course_plan, user: user, term: term) }

      it "returns all user plans" do
        get "/api/users/me/course_plans", headers: headers
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json.size).to eq(1)
        expect(json.first["id"]).to eq(plan.id)
        expect(json.first["subject"]).to eq(plan.planned_subject)
      end

      it "filters by term_uid" do
        other_term = create(:term)
        create(:course_plan, user: user, term: other_term, planned_course_number: 9999)

        get "/api/users/me/course_plans?term_uid=#{term.uid}", headers: headers
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json.size).to eq(1)
        expect(json.first["id"]).to eq(plan.id)
      end

      it "does not return other users plans" do
        other_user = create(:user)
        create(:course_plan, user: other_user, term: term)

        get "/api/users/me/course_plans", headers: headers
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json.size).to eq(1)
      end
    end
  end

  describe "GET /api/users/me/course_plans/:id" do
    let(:term) { create(:term) }
    let!(:plan) { create(:course_plan, user: user, term: term) }

    it "requires authentication" do
      get "/api/users/me/course_plans/#{plan.id}"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the plan" do
      get "/api/users/me/course_plans/#{plan.id}", headers: headers
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["id"]).to eq(plan.id)
      expect(json["subject"]).to eq(plan.planned_subject)
      expect(json["status"]).to eq("planned")
    end

    it "returns 404 for another users plan" do
      other_user = create(:user)
      other_plan = create(:course_plan, user: other_user, term: term)

      get "/api/users/me/course_plans/#{other_plan.id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/users/me/course_plans" do
    let(:term) { create(:term) }

    it "requires authentication" do
      post "/api/users/me/course_plans",
           params: { term_uid: term.uid, subject: "COMP", course_number: 1000 }.to_json,
           headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "creates a course plan" do
      post "/api/users/me/course_plans",
           params: { term_uid: term.uid, subject: "COMP", course_number: 2000, notes: "Need this class" }.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      json = response.parsed_body
      expect(json["subject"]).to eq("COMP")
      expect(json["course_number"]).to eq(2000)
      expect(json["notes"]).to eq("Need this class")
      expect(json["status"]).to eq("planned")
      expect(user.course_plans.count).to eq(1)
    end

    it "links to a course when CRN is provided" do
      course = create(:course, term: term, crn: 77777)
      post "/api/users/me/course_plans",
           params: { term_uid: term.uid, subject: course.subject, course_number: course.course_number, crn: 77777 }.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      plan = user.course_plans.last
      expect(plan.course).to eq(course)
    end

    it "returns 404 for unknown term" do
      post "/api/users/me/course_plans",
           params: { term_uid: "INVALID", subject: "COMP", course_number: 1000 }.to_json,
           headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "returns error for missing required fields" do
      post "/api/users/me/course_plans",
           params: { term_uid: term.uid, subject: "COMP" }.to_json,
           headers: headers
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /api/users/me/course_plans/:id" do
    let(:term) { create(:term) }
    let!(:plan) { create(:course_plan, user: user, term: term) }

    it "requires authentication" do
      patch "/api/users/me/course_plans/#{plan.id}",
            params: { status: "enrolled" }.to_json,
            headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "updates the plan status" do
      patch "/api/users/me/course_plans/#{plan.id}",
            params: { status: "enrolled" }.to_json,
            headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["status"]).to eq("enrolled")
      expect(plan.reload.status).to eq("enrolled")
    end

    it "updates notes" do
      patch "/api/users/me/course_plans/#{plan.id}",
            params: { notes: "Updated notes" }.to_json,
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(plan.reload.notes).to eq("Updated notes")
    end

    it "cannot update another users plan" do
      other_user = create(:user)
      other_plan = create(:course_plan, user: other_user, term: term)

      patch "/api/users/me/course_plans/#{other_plan.id}",
            params: { status: "enrolled" }.to_json,
            headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/users/me/course_plans/:id" do
    let(:term) { create(:term) }
    let!(:plan) { create(:course_plan, user: user, term: term) }

    it "requires authentication" do
      delete "/api/users/me/course_plans/#{plan.id}"
      expect(response).to have_http_status(:unauthorized)
    end

    it "deletes the plan" do
      delete "/api/users/me/course_plans/#{plan.id}", headers: headers
      expect(response).to have_http_status(:no_content)
      expect(user.course_plans.count).to eq(0)
    end

    it "cannot delete another users plan" do
      other_user = create(:user)
      other_plan = create(:course_plan, user: other_user, term: term)

      delete "/api/users/me/course_plans/#{other_plan.id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/users/me/course_plans/generate" do
    let(:term) { create(:term, :future, uid: 202730, year: 2027, season: :fall, start_date: 6.months.from_now.to_date, end_date: 10.months.from_now.to_date) }

    it "requires authentication" do
      post "/api/users/me/course_plans/generate",
           params: { term_uids: [term.uid] }.to_json,
           headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns suggestions grouped by term" do
      degree_program = create(:degree_program)
      create(:user_degree_program, user: user, degree_program: degree_program)
      create(:degree_requirement, :specific_course, degree_program: degree_program, subject: "COMP", course_number: 3000)
      create(:course, term: term, subject: "COMP", course_number: 3000, credit_hours: 3, crn: 80001)

      post "/api/users/me/course_plans/generate",
           params: { term_uids: [term.uid] }.to_json,
           headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to have_key("suggestions")
      expect(json["suggestions"]).to have_key(term.uid.to_s)
    end

    it "returns bad request without term_uids" do
      post "/api/users/me/course_plans/generate",
           params: {}.to_json,
           headers: headers
      expect(response).to have_http_status(:bad_request)
    end

    it "returns 404 for invalid term uid" do
      post "/api/users/me/course_plans/generate",
           params: { term_uids: [999999] }.to_json,
           headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/users/me/course_plans/validate" do
    let(:term) { create(:term, :current) }

    it "requires authentication" do
      post "/api/users/me/course_plans/validate",
           params: { term_uid: term.uid }.to_json,
           headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "validates a plan" do
      course = create(:course, term: term, credit_hours: 3)
      create(:course_plan, user: user, term: term, course: course,
             planned_subject: course.subject, planned_course_number: course.course_number)

      post "/api/users/me/course_plans/validate",
           params: { term_uid: term.uid }.to_json,
           headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to have_key("valid")
      expect(json).to have_key("issues")
      expect(json).to have_key("warnings")
      expect(json).to have_key("summary")
    end

    it "returns bad request without term_uid" do
      post "/api/users/me/course_plans/validate",
           params: {}.to_json,
           headers: headers
      expect(response).to have_http_status(:bad_request)
    end

    it "returns 404 for invalid term uid" do
      post "/api/users/me/course_plans/validate",
           params: { term_uid: 999999 }.to_json,
           headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
