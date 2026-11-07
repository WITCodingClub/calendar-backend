# frozen_string_literal: true

require "rails_helper"

# Issue #944: the degree_planning flag hides the My programs pages and the
# programs and degree progress API. The specs of each page and endpoint turn
# the flag on with the :degree_planning tag. This spec checks the flag off.
RSpec.describe "degree_planning flag", type: :request do
  let(:user) { create(:user, :with_processed_courses) }
  let(:planned) { create(:student_program, :planned, user: user) }

  after { Flipper.disable(FeatureFlags::DEGREE_PLANNING) }

  describe "the dashboard" do
    before { sign_in user }

    it "answers 404 on every My programs page while the flag is off" do
      get dashboard_programs_path
      expect(response).to have_http_status(:not_found)

      get edit_dashboard_academic_profile_path
      expect(response).to have_http_status(:not_found)

      post dashboard_planned_programs_path, params: { program: "gear-minor" }
      expect(response).to have_http_status(:not_found)

      delete dashboard_planned_program_path(planned.public_id)
      expect(response).to have_http_status(:not_found)
      expect(StudentProgram.exists?(planned.id)).to be(true)
    end

    it "hides the Programs nav item while the flag is off" do
      get dashboard_schedule_path

      expect(response.body).not_to include(dashboard_programs_path)
    end

    it "shows the pages to a user the flag is on for, and only to that user" do
      Flipper.enable_actor(FeatureFlags::DEGREE_PLANNING, user)

      get dashboard_programs_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(href="#{dashboard_programs_path}"))

      sign_in create(:user, :with_processed_courses)
      get dashboard_programs_path
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the API" do
    let(:headers) { auth_headers_for(user) }

    it "answers 404 on the programs and degree progress endpoints while the flag is off" do
      get "/api/user/programs", headers: headers
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "Degree planning is not enabled", "code" => "NOT_FOUND")

      post "/api/user/planned_programs", params: { program: "gear-minor" }, headers: headers
      expect(response).to have_http_status(:not_found)

      delete "/api/user/planned_programs/#{planned.public_id}", headers: headers
      expect(response).to have_http_status(:not_found)
      expect(StudentProgram.exists?(planned.id)).to be(true)

      get "/api/user/degree_progress", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "keeps the academic profile endpoint on, so the extension still sends LeopardWeb data" do
      get "/api/user/academic_profile", headers: headers

      expect(response).to have_http_status(:ok)
    end

    it "answers a user the flag is on for" do
      Flipper.enable_actor(FeatureFlags::DEGREE_PLANNING, user)

      get "/api/user/programs", headers: headers

      expect(response).to have_http_status(:ok)
    end

    it "sends the flag to the extension as degreePlanning" do
      Flipper.enable_actor(FeatureFlags::DEGREE_PLANNING, user)

      get "/api/user/feature_flags", headers: headers

      expect(response.parsed_body.dig("feature_flags", "degreePlanning")).to be(true)
    end
  end
end
