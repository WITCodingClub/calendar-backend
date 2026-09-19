# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin review search", type: :request do
  let(:admin)   { create(:user, :admin) }
  let(:faculty) { create(:faculty, first_name: "Ada", last_name: "Byron") }

  let!(:group_work) { create(:rmp_rating, faculty: faculty, comment: "Lots of group projects.") }
  let!(:tough_exams) { create(:rmp_rating, faculty: faculty, comment: "The exams are brutal.") }

  before do
    stub_request(:get, "https://api.github.com/repos/WITCodingClub/calendar/releases/latest")
      .to_return(status: 200, body: { tag_name: "v0.0.0" }.to_json)
    allow(TwentyFiveLiveSyncJob).to receive(:in_progress?).and_return(false)
    sign_in admin
  end

  it "lists every review without a query" do
    get admin_rmp_ratings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Lots of group projects.", "The exams are brutal.")
  end

  it "keeps the reviews that contain the words" do
    get admin_rmp_ratings_path, params: { q: "group projects" }

    expect(response.body).to include("Lots of group projects.")
    expect(response.body).not_to include("The exams are brutal.")
  end

  it "ranks by meaning when asked", :semantic_search do
    give_embedding(group_work, 0.05)
    give_embedding(tough_exams, 0.95)
    stub_openai_embeddings([ embedding_vector(0.0) ])

    get admin_rmp_ratings_path, params: { q: "team assignments", semantic: "1" }

    expect(response.body).to include("Lots of group projects.")
    expect(response.body.index("Lots of group projects.")).to be < response.body.index("The exams are brutal.")
  end

  it "says so when a search by meaning falls back to the words", :embeddings do
    get admin_rmp_ratings_path, params: { q: "team assignments", semantic: "1" }

    expect(response.body).to include("Search by meaning is off")
  end
end
