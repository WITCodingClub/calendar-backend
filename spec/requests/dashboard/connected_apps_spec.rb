# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::ConnectedApps", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "lists the apps that hold a token in Settings" do
    create(:oauth_access_token, resource_owner_id: user.id,
                                application: create(:oauth_application, name: "Claude", redirect_uri: "https://claude.ai/cb"))

    get dashboard_settings_path

    expect(response.body).to include("Connected apps", "Claude", "claude.ai")
  end

  it "shows no card when no app holds a token" do
    get dashboard_settings_path

    expect(response.body).not_to include("Connected apps")
  end

  it "revokes the app's tokens and grants for this user only" do
    token       = create(:oauth_access_token, resource_owner_id: user.id)
    grant       = create(:oauth_access_grant, resource_owner_id: user.id, application: token.application)
    other_token = create(:oauth_access_token, application: token.application)

    delete dashboard_connected_app_path(token.application)

    expect(response).to redirect_to(dashboard_settings_path)
    expect(flash[:notice]).to eq("#{token.application.name} disconnected.")
    expect(token.reload).to be_revoked
    expect(grant.reload).to be_revoked
    expect(other_token.reload).not_to be_revoked
  end

  it "does not find an app that holds no token for this user" do
    other_token = create(:oauth_access_token)

    delete dashboard_connected_app_path(other_token.application)

    expect(response).to redirect_to(dashboard_settings_path)
    expect(flash[:alert]).to eq("Connected app not found.")
    expect(other_token.reload).not_to be_revoked
  end
end
