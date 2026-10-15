# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::IcsFeeds", type: :request do
  let(:user) { create(:user, :with_processed_courses) }

  before { sign_in user }

  describe "GET /dashboard/ics_feed" do
    it "shows the privacy warning before the URL field (#698)" do
      get dashboard_ics_feed_path

      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML(response.body)
      warning = page.at_css("#ics-privacy-warning")
      field = page.at_css("#ics-url-field")
      expect(warning.text).to include("Keep this URL private.")
      expect(field["aria-describedby"]).to eq("ics-privacy-warning")
      expect(response.body.index('id="ics-privacy-warning"')).to be < response.body.index('id="ics-url-field"')
    end

    it "makes a token for a user who has none" do
      user.update_column(:calendar_token, nil) # rubocop:disable Rails/SkipsModelValidations

      get dashboard_ics_feed_path

      token = user.reload.calendar_token
      expect(token).to be_present
      expect(Nokogiri::HTML(response.body).at_css("#ics-url-field")["value"]).to include(token)
    end
  end
end
