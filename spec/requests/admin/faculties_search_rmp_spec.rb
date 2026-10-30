# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin RateMyProfessors search", type: :request do
  let(:admin) { create(:user, :super_admin) }

  before do
    stub_request(:get, "https://api.github.com/repos/WITCodingClub/calendar/releases/latest")
      .to_return(status: 200, body: { tag_name: "v0.0.0" }.to_json)
    allow(TwentyFiveLive::SyncJob).to receive(:in_progress?).and_return(false)
    stub_request(:post, Faculties::RateMyProfessorClient::BASE_URL)
      .with(body: hash_including("operationName" => "NewSearchTeachersQuery"))
      .to_return(status: 200, body: file_fixture("rate_my_professor/search_spelling_variant.json").read,
                 headers: { "Content-Type" => "application/json" })
    sign_in admin
  end

  it "marks a teacher with a different spelling of the first name as the best match" do
    faculty = create(:faculty, first_name: "Ahmad", last_name: "Qorvin")

    get search_rmp_admin_faculty_path(faculty)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ahmed", "Best match")
  end

  it "returns the best match id as JSON" do
    faculty = create(:faculty, first_name: "Ahmad", last_name: "Qorvin")

    get search_rmp_admin_faculty_path(faculty, format: :json)

    expect(response.parsed_body["best_match_id"]).to eq("VGVhY2hlci03Nzc3Nzc=")
  end
end
