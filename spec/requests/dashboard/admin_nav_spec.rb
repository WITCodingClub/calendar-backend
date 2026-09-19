# frozen_string_literal: true

require "rails_helper"

# The user layout puts the Admin nav items in admin_tool blocks. The gem
# checks User#admin_access?, so every access level above user sees them.
RSpec.describe "Dashboard admin nav", type: :request do
  def admin_links
    Nokogiri::HTML(response.body).css(".admin-tools a[href='#{admin_root_path}']")
  end

  it "hides the Admin nav items from a user" do
    sign_in create(:user)

    get dashboard_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(%(href="#{admin_root_path}"))
  end

  %i[admin super_admin owner].each do |level|
    it "shows the Admin nav items to #{level.to_s.humanize.downcase}" do
      sign_in create(:user, access_level: level)

      get dashboard_root_path

      expect(response).to have_http_status(:ok)
      # One in the desktop rail, one in the mobile bottom nav.
      expect(admin_links.size).to eq(2)
    end
  end
end
