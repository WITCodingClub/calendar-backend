# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin RateMyProfessors linking", type: :request do
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
    faculty = create(:faculty, first_name: "Muhammad", last_name: "Qorvin")

    get search_rmp_admin_faculty_path(faculty)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Muhammed", "Best match")
  end

  it "returns the best match id as JSON" do
    faculty = create(:faculty, first_name: "Muhammad", last_name: "Qorvin")

    get search_rmp_admin_faculty_path(faculty, format: :json)

    expect(response.parsed_body["best_match_id"]).to eq("VGVhY2hlci03Nzc3Nzc=")
  end

  describe "missing RMP IDs" do
    include ActiveSupport::Testing::TimeHelpers

    around { |example| travel_to(Date.new(2026, 10, 1)) { example.run } }

    def teaching(name, term, status: :active)
      create(:faculty, last_name: name).tap do |faculty|
        create(:course_faculty, faculty: faculty, course: create(:course, term: term, status: status))
      end
    end

    it "lists only professors with a course that is not cancelled in the current or a later term" do
      current = create(:term, year: 2026, season: :fall)
      teaching("Currentteach", current)
      teaching("Pastteach", create(:term, year: 2025, season: :spring))
      teaching("Cancelledteach", current, status: :cancelled)

      get missing_rmp_ids_admin_faculties_path

      expect(response.body).to include("Currentteach")
      expect(response.body).not_to include("Pastteach", "Cancelledteach")
    end

    it "queues a search only for those professors" do
      current = create(:term, year: 2026, season: :fall)
      listed = teaching("Currentteach", current)
      teaching("Pastteach", create(:term, year: 2025, season: :spring))

      expect { post batch_auto_fill_admin_faculties_path }
        .to have_enqueued_job(Faculties::UpdateRatingsJob).with(listed.id).exactly(:once)
      expect(Faculties::UpdateRatingsJob).not_to have_been_enqueued.with(satisfy { |id| id != listed.id })
    end
  end
end
