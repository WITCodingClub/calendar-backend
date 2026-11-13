# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/api/user/registration_plans", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:term) { create(:term, uid: 202720, year: 2027, season: :spring) }
  let(:body) do
    {
      courses: [
        { code: "COMP 3350", crns: %w[20410 20411], fills: { kind: "course", label: "Algorithms" } },
        { code: "MATH 2300", crns: [ "20520" ], fills: { kind: "choice", label: "Discrete Mathematics or Linear Algebra" } },
        { code: "PHIL 2100", crns: [ "20610" ], fills: nil }
      ],
      preferences: { earliest: "09:00", latest: "17:00", day_off: "any", open_only: true }
    }
  end

  def put_plan(params = body, uid: term.uid, as_user: user)
    put "/api/user/registration_plans/#{uid}", params: params, headers: auth_headers_for(as_user), as: :json
  end

  context "with the degree_planning flag", :degree_planning do
    before do
      lecture = create(:course, term: term, crn: 20410)
      create(:course_meeting_time, course: lecture, day_of_week: :monday, begin_time: 1000, end_time: 1115)
      math = create(:course, term: term, crn: 20520)
      create(:course_meeting_time, course: math, day_of_week: :monday, begin_time: 1100, end_time: 1215)
    end

    it "saves a plan with conflicts and returns it with the schedule check" do
      put_plan

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["term"]).to eq("uid" => 202720, "name" => "Spring 2027")
      expect(json["crns"]).to eq(%w[20410 20411 20520 20610])
      expect(json["courses"].first).to eq("code" => "COMP 3350", "crns" => %w[20410 20411],
                                          "fills" => { "kind" => "course", "label" => "Algorithms" })
      expect(json["courses"].last["fills"]).to be_nil
      expect(json["preferences"]).to eq("earliest" => "09:00", "latest" => "17:00", "day_off" => "any", "open_only" => true)
      expect(json["schedule_check"].keys).to match_array(%w[sections not_found cancelled conflicts link_problems duplicates totals])
      expect(json["schedule_check"]["conflicts"].first["crns"]).to eq([ 20410, 20520 ])
      expect(json["schedule_check"]["not_found"]).to eq([ 20411, 20610 ])
      expect(json["updated_at"]).to be_present
      expect(user.registration_plans.count).to eq(1)
    end

    it "replaces the plan on a second PUT" do
      put_plan
      put_plan({ courses: [ { code: "COMP 3350", crns: [ "20410" ], fills: nil } ] })

      expect(response).to have_http_status(:ok)
      plan = user.registration_plans.sole
      expect(plan.crns).to eq([ "20410" ])
      expect(plan.preferences).to eq({})
    end

    it "updates the plan when a parallel PUT saved it first" do
      # The first save runs as if another request inserted the plan after
      # this one looked: the unique index raises, and the retry updates.
      first = true
      allow_any_instance_of(RegistrationPlan).to receive(:save).and_wrap_original do |original, *args|
        next original.call(*args) unless first

        first = false
        create(:registration_plan, user: user, term: term)
        original.call(validate: false)
      end

      put_plan

      expect(response).to have_http_status(:ok)
      expect(user.registration_plans.sole.crns).to eq(%w[20410 20411 20520 20610])
    end

    it "updates the plan when a parallel PUT saved it before the validation ran" do
      first = true
      allow_any_instance_of(RegistrationPlan).to receive(:save).and_wrap_original do |original, *args|
        if first
          first = false
          create(:registration_plan, user: user, term: term)
        end
        original.call(*args)
      end

      put_plan

      expect(response).to have_http_status(:ok)
      expect(user.registration_plans.sole.crns).to eq(%w[20410 20411 20520 20610])
    end

    it "answers 422 for a bad body" do
      put_plan({ preferences: {} })
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to include("code" => "VALIDATION_FAILED", "error" => a_string_including("Courses must be a list"))

      put_plan({ courses: [ { code: "COMP 3350", crns: [ "2041a" ] } ] })
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("not digits")

      put_plan({ courses: Array.new(16) { |i| { code: "COMP #{i}", crns: [ (20_000 + i).to_s ] } } })
      expect(response).to have_http_status(:unprocessable_content)
      expect(user.registration_plans).to be_empty
    end

    it "answers 404 for an unknown term, and a non-digit term matches no route" do
      put_plan(uid: 199910)
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq("Term not found")

      get "/api/user/registration_plans/spring", headers: auth_headers_for(user)
      expect(response).to have_http_status(:not_found)
    end

    it "shows one plan with a fresh schedule check" do
      create(:registration_plan, user: user, term: term, courses: [ { "code" => "COMP 3350", "crns" => [ "20410" ], "fills" => nil } ])

      get "/api/user/registration_plans/#{term.uid}", headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["schedule_check"]["sections"].pluck("crn")).to eq([ 20410 ])
    end

    it "lists the plans newest term first, without the schedule check" do
      fall = create(:term, uid: 202710, year: 2026, season: :fall)
      create(:registration_plan, user: user, term: fall)
      travel_to Time.utc(2026, 11, 11, 18, 4) do
        create(:registration_plan, user: user, term: term,
                                   courses: [ { "code" => "COMP 3350", "crns" => %w[20410 20411] },
                                              { "code" => "MATH 2300", "crns" => [ "20520" ] } ])
      end
      create(:registration_plan)

      get "/api/user/registration_plans", headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok)
      plans = response.parsed_body["plans"]
      expect(plans.pluck("term")).to eq([ { "uid" => 202720, "name" => "Spring 2027" }, { "uid" => 202710, "name" => "Fall 2026" } ])
      expect(plans.first).to eq("term" => { "uid" => 202720, "name" => "Spring 2027" }, "crns" => %w[20410 20411 20520],
                                "course_count" => 2, "updated_at" => "2026-11-11T18:04:00Z")
    end

    it "deletes a plan" do
      create(:registration_plan, user: user, term: term)

      delete "/api/user/registration_plans/#{term.uid}", headers: auth_headers_for(user)

      expect(response).to have_http_status(:no_content)
      expect(user.registration_plans).to be_empty
    end

    it "does not reach another student's plan" do
      other = create(:registration_plan, term: term)

      get "/api/user/registration_plans/#{term.uid}", headers: auth_headers_for(user)
      expect(response).to have_http_status(:not_found)

      delete "/api/user/registration_plans/#{term.uid}", headers: auth_headers_for(user)
      expect(response).to have_http_status(:not_found)

      get "/api/user/registration_plans", headers: auth_headers_for(user)
      expect(response.parsed_body["plans"]).to be_empty

      put_plan
      expect(other.reload.crns).not_to eq(%w[20410 20411 20520 20610])
      expect(RegistrationPlan.count).to eq(2)
    end
  end

  context "without the degree_planning flag" do
    it "answers 404 on every route" do
      create(:registration_plan, user: user, term: term)

      get "/api/user/registration_plans", headers: auth_headers_for(user)
      expect(response).to have_http_status(:not_found)
      get "/api/user/registration_plans/#{term.uid}", headers: auth_headers_for(user)
      expect(response).to have_http_status(:not_found)
      put_plan
      expect(response).to have_http_status(:not_found)
      delete "/api/user/registration_plans/#{term.uid}", headers: auth_headers_for(user)
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq("Degree planning is not enabled")
      expect(user.registration_plans.count).to eq(1)
    end
  end
end
