# frozen_string_literal: true

# Token-gated and public data feeds: the ICS calendar and the CSV reports.

# ICS calendar feed (public, token-gated)
get "/calendar/:calendar_token", to: "calendars#show", as: :calendar, defaults: { format: :ics }

# Public CSV exports for BI tools (Power BI Web connector)
get "/reports/meeting_times", to: "reports#meeting_times", as: :meeting_times_report, defaults: { format: :csv }
get "/reports/sections", to: "reports#sections", as: :sections_report, defaults: { format: :csv }
get "/reports/terms", to: "reports#terms", as: :terms_report, defaults: { format: :csv }
