# frozen_string_literal: true

# The JSON API: the public catalog API and the JWT API for the extension.

# Public catalog API (no auth, read-only course schedule data)
namespace :api do
  # The GraphQL endpoint moved under /api/v1. 308 keeps the method and body.
  post "graphql", to: redirect("/api/v1/graphql", status: 308)

  namespace :v1 do
    post "graphql", to: "/api/graphql#execute"

    namespace :catalog do
      get "terms",            to: "terms#index"
      get "terms/current",    to: "terms#current"
      get "terms/next",       to: "terms#next"
      get "terms/:uid",       to: "terms#show", as: :term, constraints: { uid: /\d+/ }
      get "subjects",         to: "subjects#index"
      get "sections",         to: "sections#index"
      get "sections/:crn",    to: "sections#show", as: :section, constraints: { crn: /\d+/ }
      get "sections/:crn/similar", to: "sections#similar", as: :similar_sections, constraints: { crn: /\d+/ }
      get "reviews",          to: "reviews#index"
      get "instructors",      to: "instructors#index"
      get "instructors/:pub_id", to: "instructors#show", as: :instructor
      get "instructors/:pub_id/similar", to: "instructors#similar", as: :similar_instructors
    end
  end
end

# API routes (JWT-authenticated)
namespace :api do
  # Anonymous usage counts from the extension, for Grafana. No token.
  post "extension_events",                       to: "extension_events#create"

  post "user/onboard",                           to: "onboardings#create"
  get "user",                                    to: "profiles#show"
  post "user/google_calendar",                   to: "google_calendars#create"
  post "user/google_calendar/emails",            to: "google_calendars#add_email"
  delete "user/google_calendar/emails",          to: "google_calendars#remove_email"
  get "user/busy_blocks",                        to: "busy_blocks#show"
  get "user/oauth_credentials",                  to: "oauth_credentials#index"
  delete "user/oauth_credentials/:credential_id", to: "oauth_credentials#destroy"
  post "user/microsoft_calendar",                to: "microsoft_calendars#create"
  patch "user/microsoft_calendar",               to: "microsoft_calendars#update"

  # Passkeys — a quick second sign-in for an account Google already vouched
  # for. The two authentication routes are the only unauthenticated ones.
  get    "user/passkeys",                      to: "passkeys#index"
  post   "user/passkeys/registration_options", to: "passkeys#registration_options"
  post   "user/passkeys",                      to: "passkeys#create"
  delete "user/passkeys/:passkey_id",          to: "passkeys#destroy"
  post   "user/passkeys/handoff",              to: "passkeys#handoff"
  post   "user/passkeys/authentication_options", to: "passkeys#authentication_options"
  post   "user/passkeys/authenticate",           to: "passkeys#authenticate"
  post   "user/passkeys/exchange",               to: "passkeys#exchange"

  # Sessions — see where the account is signed in, and end any of it.
  get    "user/sessions",             to: "sessions#index"
  delete "user/sessions/:session_id", to: "sessions#destroy"
  post   "user/sessions/revoke_all",  to: "sessions#revoke_all"

  get "user/processed_events",         to: "processed_events#index"
  get "user/processed_events/status",  to: "processed_events#processing_status"

  get "user/extension_config",           to: "extension_configs#show"
  put "user/extension_config",           to: "extension_configs#update"

  get "user/feature_flags",             to: "feature_flags#index"

  get   "user/notifications",           to: "notifications#show"
  patch "user/notifications",           to: "notifications#update"

  # Friends system
  get    "friends",                                   to: "friends#index"
  get    "friends/meetings",                          to: "friends/meetings#index"
  post   "friends/meetings",                          to: "friends/meetings#create"
  get    "friends/meetings/:id",                      to: "friends/meetings#show"
  patch  "friends/meetings/:id",                      to: "friends/meetings#update"
  delete "friends/meetings/:id",                      to: "friends/meetings#destroy"
  delete "friends/meetings/:id/attendance",           to: "friends/meetings#leave"
  get    "friends/requests",                          to: "friends/requests#index"
  post   "friends/requests",                          to: "friends/requests#create"
  post   "friends/requests/:request_id/accept",       to: "friends/requests#accept"
  post   "friends/requests/:request_id/decline",      to: "friends/requests#decline"
  delete "friends/requests/:request_id",              to: "friends/requests#destroy"
  # Friend groups. Every route answers 404 while the friend_groups flag is off.
  get    "friends/groups",                            to: "friends/groups#index"
  post   "friends/groups",                            to: "friends/groups#create"
  get    "friends/groups/:group_id",                  to: "friends/groups#show"
  patch  "friends/groups/:group_id",                  to: "friends/groups#update"
  delete "friends/groups/:group_id",                  to: "friends/groups#destroy"
  post   "friends/groups/:group_id/members",          to: "friends/groups#add_member"
  delete "friends/groups/:group_id/members/:friend_id", to: "friends/groups#remove_member"
  delete "friends/:friend_id",                        to: "friends#destroy"
  patch  "friends/:friend_id/expiry",                 to: "friends#update_expiry"
  get    "friends/:friend_id/processed_events",       to: "friends/schedules#processed_events"
  get    "friends/:friend_id/processed_events/status", to: "friends/schedules#processed"
  get    "friends/:friend_id/visibility",             to: "friends/visibilities#show"
  patch  "friends/:friend_id/visibility",             to: "friends/visibilities#update"
  get    "friends/:friend_id/busy_blocks",            to: "friends/schedules#busy_blocks"

  # One-time meeting links for people who are not friends (#652).
  get    "meeting_links",                             to: "meeting_links#index"
  post   "meeting_links",                             to: "meeting_links#create"
  delete "meeting_links/:id",                         to: "meeting_links#destroy"

  # Course processing
  post "process_courses",       to: "courses#process_courses"
  post "process_courses/batch", to: "courses#process_courses_batch"
  post "courses/reprocess",  to: "courses#reprocess"

  # Calendar preferences (global + per event-type + per university calendar category)
  resources :calendar_preferences, only: [ :index, :show, :update, :destroy ] do
    collection { post :preview }
  end

  get "user/preferences/version", to: "preference_versions#show"

  # Per-event preferences (meeting time or calendar event)
  post "meeting_times/preferences", to: "event_preferences#batch_show"
  resources :meeting_times, only: [] do
    resource :preference, controller: "event_preferences", only: [ :show, :update, :destroy ]
  end
  resources :calendar_events, only: [] do
    resource :preference, controller: "event_preferences", only: [ :show, :update, :destroy ]
  end

  # University calendar events
  resources :university_calendar_events, only: [ :index, :show ] do
    collection do
      get  :categories
      get  :holidays
      post :sync
    end
  end

  draw :api_legacy

  match "*path", to: "catch_all#not_found", via: :all
end
