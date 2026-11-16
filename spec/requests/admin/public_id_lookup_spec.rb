# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin public id lookup", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:term)  { create(:term) }

  before do
    stub_request(:get, "https://api.github.com/repos/WITCodingClub/calendar/releases/latest")
      .to_return(status: 200, body: { tag_name: "v0.0.0" }.to_json)
    sign_in admin
  end

  it "finds a record by the prefix its model declares" do
    get admin_lookup_public_id_path(term.public_id.upcase)

    expect(response.parsed_body).to include("type" => "Term", "path" => admin_term_path(term))
  end

  it "answers 404 for an unknown prefix and for a missing record" do
    get admin_lookup_public_id_path("zzz_abc")
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body["error"]).to eq("Unknown public ID prefix: zzz")

    get admin_lookup_public_id_path("usr_nothere1")
    expect(response).to have_http_status(:not_found)
  end

  it "redirects to the record's admin page, or home with an alert" do
    get admin_redirect_public_id_path(admin.public_id)
    expect(response).to redirect_to(admin_user_path(admin))

    get admin_redirect_public_id_path("zzz_abc")
    expect(response).to redirect_to(admin_root_path)
    expect(flash[:alert]).to eq("Unknown public ID prefix: zzz")
  end

  it "opens a user page by public id, hashid, or database id" do
    [ admin.public_id, admin.hashid, admin.id ].each do |id|
      get admin_user_path(id)
      expect(response).to have_http_status(:ok)
    end
  end
end
