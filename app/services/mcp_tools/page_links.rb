# frozen_string_literal: true

module McpTools
  # Links from a tool result to the WIT Calendar pages where the student can
  # see or change the same data. Each link is an MCP resource_link content
  # item (MCP 2025-06-18). A client can show it as a link to open.
  #
  # A tool names its links with BaseTool.links. Each URL comes from a route
  # helper and McpTools::Server.url_options, so it has the host of the
  # environment. A URL holds only the public ids that the page itself uses,
  # never a token. Most pages need a signed-in session: the student signs in
  # in the browser.
  module PageLinks
    MIME_TYPE = "text/html"

    # The Connected apps card on the dashboard settings page, which lists the
    # permissions of each app.
    CONNECTED_APPS_ANCHOR = "connected-apps"

    module_function

    def page_link(name:, title:, url:, description: nil)
      { type: "resource_link", uri: url, name: name, title: title, description: description, mimeType: MIME_TYPE }.compact
    end

    # page_url(:dashboard_schedule_url, term_uid: 202610)
    def page_url(helper, *args, **params)
      Rails.application.routes.url_helpers.public_send(helper, *args, **Server.url_options, **params)
    end

    # The calendar-wide event settings and the university event sync.
    def calendar_settings_link
      page_link(
        name:        "wit-calendar-calendar-settings",
        title:       "Calendar settings on WIT Calendar",
        url:         page_url(:dashboard_calendar_preferences_url),
        description: "The event title, description, location, color, and reminders for all your classes, " \
                     "each kind of class, and university events."
      )
    end

    def connected_apps_link
      page_link(
        name:        "wit-calendar-connected-apps",
        title:       "Connected apps on WIT Calendar",
        url:         page_url(:dashboard_settings_url, anchor: CONNECTED_APPS_ANCHOR),
        description: "The apps that can use your WIT Calendar data, with the permissions each app has."
      )
    end
  end
end
