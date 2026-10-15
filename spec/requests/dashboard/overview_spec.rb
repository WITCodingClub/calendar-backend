# frozen_string_literal: true

require "rails_helper"

# The Overview page shows a setup checklist until every step is done (#698).
RSpec.describe "Dashboard::Overview", type: :request do
  let(:user) { create(:user, :with_processed_courses) }

  before { sign_in user }

  def checklist
    Nokogiri::HTML(response.body).at_css("section[aria-labelledby='setup-heading']")
  end

  describe "GET /dashboard" do
    it "shows the checklist with a link to connect a calendar when no calendar is connected" do
      get dashboard_root_path

      expect(response).to have_http_status(:ok)
      expect(checklist).to be_present
      expect(checklist.text).to include("2 of 3 done")
      expect(checklist.at_css("a[href='#{dashboard_connected_accounts_path}']").text).to include("Connect a calendar")
    end

    it "hides the checklist when every step is done" do
      create(:course_calendar, oauth_credential: create(:oauth_credential, user: user))

      get dashboard_root_path

      expect(response).to have_http_status(:ok)
      expect(checklist).to be_nil
    end

    it "asks for an import when the user has no courses in the current term" do
      create(:course_calendar, oauth_credential: create(:oauth_credential, user: user))
      current_term = create(:term, year: Time.zone.today.year + 1)
      allow(Term).to receive(:current).and_return(current_term)

      get dashboard_root_path

      expect(checklist.text).to include("Import your schedule")
      expect(checklist.text).to include("import your courses for #{current_term.name}")
      expect(checklist.text).to include("2 of 3 done")
    end

    it "links an admin with no courses to the extension" do
      admin = create(:user, :admin)
      sign_in admin

      get dashboard_root_path

      expect(checklist.css("a[href='#{Rails.configuration.x.extension_install_url}']")).to be_present
      expect(checklist.text).to include("0 of 3 done")
    end
  end
end
