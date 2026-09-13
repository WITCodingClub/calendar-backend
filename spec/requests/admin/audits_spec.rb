# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin console audits", type: :request do
  let(:admin) do
    User.create!(email: "auditor@wit.edu", password: "password123", confirmed_at: Time.current,
                 first_name: "Ada", last_name: "Lovelace", access_level: :admin)
  end
  let(:other_admin) do
    User.create!(email: "other-auditor@wit.edu", password: "password123", confirmed_at: Time.current,
                 first_name: "Grace", last_name: "Hopper", access_level: :admin)
  end
  let(:console_user) { Console1984::User.create!(username: "deploy") }
  let!(:console_session) { Console1984::Session.create!(user: console_user, reason: "Fix a stuck sync") }

  context "when an admin is signed in" do
    before { sign_in admin }

    it "lists console sessions" do
      get "/admin/audits"

      expect(response).to have_http_status(:ok)
    end

    it "shows a session with the names of other auditors" do
      console_session.audits.create!(auditor: other_admin, status: :approved)

      get "/admin/audits/sessions/#{console_session.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Grace Hopper")
    end

    it "records an audit by the signed-in admin" do
      expect do
        post "/admin/audits/sessions/#{console_session.id}/audits",
             params: { audit: { status: "flagged", notes: "Check this" } }
      end.to change(Audits1984::Audit, :count).by(1)

      audit = Audits1984::Audit.last
      expect(audit.auditor).to eq(admin)
      expect(audit).to be_flagged
    end
  end

  context "when a non-admin is signed in" do
    it "does not show console sessions" do
      sign_in User.create!(email: "student@wit.edu", password: "password123", confirmed_at: Time.current)

      get "/admin/audits"

      expect(response).to redirect_to(dashboard_root_path)
    end
  end
end
