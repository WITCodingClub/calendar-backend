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

    # The first protocol version with the resource_link content type. A
    # client on an older version can check content against a closed list of
    # types and refuse the whole result, so it gets no links.
    FIRST_PROTOCOL_VERSION = "2025-06-18"

    # The version of a request with no MCP-Protocol-Version header (MCP
    # Streamable HTTP transport).
    DEFAULT_PROTOCOL_VERSION = "2025-03-26"

    PROTOCOL_VERSION_HEADER = "MCP-Protocol-Version"

    # The Connected apps card on the dashboard settings page, which lists the
    # permissions of each app.
    CONNECTED_APPS_ANCHOR = "connected-apps"

    module_function

    # True when the client of this tool call can read resource_link items.
    # Versions are dates, so a string comparison orders them.
    def supported?(server_context)
      protocol_version(server_context) >= FIRST_PROTOCOL_VERSION
    end

    # The version of the 2026-07-28 _meta envelope comes first, then the
    # MCP-Protocol-Version header of the HTTP request.
    def protocol_version(server_context)
      key  = MCP::RequestEnvelope::PROTOCOL_VERSION_META_KEY
      meta = server_context[:_meta]
      versions = [
        (server_context.protocol_version if server_context.respond_to?(:protocol_version)),
        (meta[key.to_sym] || meta[key] if meta.is_a?(Hash)),
        server_context[:request]&.headers&.[](PROTOCOL_VERSION_HEADER)
      ]

      versions.find { |version| version.is_a?(String) && version.present? } || DEFAULT_PROTOCOL_VERSION
    end

    def page_link(name:, title:, url:, description: nil)
      { type: "resource_link", uri: url, name: name, title: title, description: description, mimeType: MIME_TYPE }.compact
    end

    # page_url(:dashboard_schedule_url, term_uid: 202610)
    def page_url(helper, *args, **params)
      Rails.application.routes.url_helpers.public_send(helper, *args, **Server.url_options, **params)
    end

    # The settings page skips the onboarding check, so every student can
    # open it.
    def connected_apps_link
      page_link(
        name:        "wit-calendar-connected-apps",
        title:       "Connected apps on WIT Calendar",
        url:         page_url(:dashboard_settings_url, anchor: CONNECTED_APPS_ANCHOR),
        description: "The apps that can use your WIT Calendar data, with the permissions each app has."
      )
    end

    # The methods below run on a tool instance (BaseTool includes this
    # module), because they read user.
    private

    # A link to a dashboard page that sends a student with no processed
    # courses to onboarding (Dashboard::ApplicationController). That student
    # gets no link.
    def onboarded_page_link(**)
      page_link(**) if user.onboarding_complete?
    end

    # The calendar-wide event settings and the university event sync.
    def calendar_settings_link
      onboarded_page_link(
        name:        "wit-calendar-calendar-settings",
        title:       "Calendar settings on WIT Calendar",
        url:         page_url(:dashboard_calendar_preferences_url),
        description: "The event title, description, location, color, and reminders for all your classes, " \
                     "each kind of class, and university events."
      )
    end
  end
end
