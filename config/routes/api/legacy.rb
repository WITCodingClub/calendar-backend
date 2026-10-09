# frozen_string_literal: true

# Old paths of the JWT API that published extension builds still call. Each
# one runs the same action as its new path. Api::LegacyRouteCounting counts the
# requests in calendar_api_legacy_requests_total, by path. Remove a path when
# its count stays at zero after the extension release that stops calling it.
#
# This file is drawn inside namespace :api in config/routes/api.rb, before the
# catch-all route.
{
  [ :get,    "user/email" ]                           => "profiles#email",
  [ :get,    "user/ics_url" ]                         => "profiles#ics_url",
  [ :post,   "user/gcal" ]                            => "google_calendars#create",
  [ :get,    "user/flag_enabled" ]                    => "feature_flags#show",
  [ :get,    "user/notifications_status" ]            => "notifications#show",
  [ :post,   "user/notifications/disable" ]           => "notifications#disable",
  [ :post,   "user/notifications/enable" ]            => "notifications#enable",
  [ :post,   "user/is_processed" ]                    => "processed_events#processing_status",
  [ :post,   "user/processed_events" ]                => "processed_events#index",
  [ :post,   "friends/:friend_id/is_processed" ]      => "friends/schedules#processed",
  [ :post,   "friends/:friend_id/processed_events" ]  => "friends/schedules#processed_events",
  [ :get,    "terms/current_and_next" ]               => "terms#current_and_next"
}.each do |(verb, path), action|
  send(verb, path, to: action, defaults: { legacy_route: "#{verb.upcase} #{path}" })
end

# The old name of the calendar event preference routes.
resources :google_calendar_events, only: [], defaults: { legacy_route: "google_calendar_events/:id/preference" } do
  resource :preference, controller: "event_preferences", only: [ :show, :update, :destroy ]
end
