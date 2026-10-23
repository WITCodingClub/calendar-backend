# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/api/user/academic_profile", type: :request do
  let(:user) { create(:user) }

  let(:payload) do
    {
      source:         "leopardweb",
      level:          "Undergraduate",
      class_standing: "Sophomore",
      admit_type:     "Freshman Admit (Domestic)",
      admit_term:     "Fall 2025",
      programs:       [
        { role: "major", code: "BCOS3", name: "Computer Science", degree: "Bachelor of Science",
          college: "The School of Comp & Data Sci", department: "Computer Science & Networking",
          concentration: nil, study_path: nil, catalog_term: "Fall 2025" },
        { role: "minor", code: nil, name: "Computer Networking", catalog_term: "Fall 2025" }
      ]
    }
  end

  describe "GET" do
    it "returns null fields and no programs before the first sync" do
      get "/api/user/academic_profile", headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("level" => nil, "admit_term" => nil, "programs" => [])
    end

    it "returns only the active programs" do
      create(:academic_profile, user: user, admit_term_uid: 202610)
      active = create(:student_program, user: user)
      create(:student_program, :ended, user: user)

      get "/api/user/academic_profile", headers: auth_headers_for(user)

      body = response.parsed_body
      expect(body).to include("admit_term" => "Fall 2025", "admit_term_code" => "202610")
      expect(body["programs"].pluck("id")).to eq([ active.public_id ])
      expect(body["programs"].first).to include("catalog_term" => "Fall 2025", "catalog_term_code" => "202610",
                                                "catalog_year" => "2025-2026", "matched" => nil)
    end
  end

  describe "PUT" do
    it "stores the profile and returns it" do
      put "/api/user/academic_profile", params: payload, headers: auth_headers_for(user), as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include("level" => "Undergraduate", "class_standing" => "Sophomore",
                              "admit_term" => "Fall 2025", "admit_term_code" => "202610")
      expect(body["programs"].map { |program| program.values_at("role", "code", "name", "source") })
        .to eq([ [ "major", "BCOS3", "Computer Science", "leopardweb" ],
                 [ "minor", nil, "Computer Networking", "leopardweb" ] ])
    end

    it "answers 422 with invalid_term for a term it cannot read" do
      put "/api/user/academic_profile", params: payload.merge(admit_term: "Autumn 2025"),
                                        headers: auth_headers_for(user), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to include("code" => "invalid_term")
      expect(user.reload.academic_profile).to be_nil
    end

    it "answers 422 with invalid_profile when programs is missing" do
      put "/api/user/academic_profile", params: payload.except(:programs), headers: auth_headers_for(user), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to include("code" => "invalid_profile", "error" => "programs must be a list")
    end
  end
end
