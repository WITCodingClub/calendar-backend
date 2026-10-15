# frozen_string_literal: true

module Dashboard
  module NavHelper
    # The pages that the mobile bottom nav puts in its More sheet. The desktop
    # rail lists each of them. The More item is active on any of these pages.
    def dashboard_more_items
      [
        { path: dashboard_connected_accounts_path, label: "Accounts", icon: "link" },
        { path: dashboard_ics_feed_path, label: "ICS Feed", icon: "rss" },
        { path: dashboard_notifications_path, label: "Notifications", icon: "bell" },
        { path: dashboard_settings_path, label: "Settings", icon: "cog" }
      ]
    end

    # True when the request is for the nav item's page, or for a page under it.
    # The dashboard root ("/dashboard") matches only itself, so Overview is not
    # active on every dashboard page.
    def dashboard_nav_active?(path)
      request.path == path || (path.split("/").length > 2 && request.path.start_with?("#{path}/"))
    end
  end
end
