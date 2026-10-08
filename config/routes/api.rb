# frozen_string_literal: true

# The JSON API: the public catalog API and the JWT API for the extension.

# Public catalog API (no auth, read-only course schedule data)
namespace :api do
  post "graphql", to: "graphql#execute"

  namespace :v1 do
    namespace :catalog do
      get "terms",            to: "terms#index"
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

  post "user/onboard",                           to: "users#onboard"
  post "user/gcal",                              to: "users#request_g_cal"
  post "user/gcal/add_email",                    to: "users#add_email_to_g_cal"
  delete "user/gcal/remove_email",               to: "users#remove_email_from_g_cal"
  get "user/busy_blocks",                        to: "users#busy_blocks"
  get "user/id",                                   to: "users#get_id"
  get "user/email",                              to: "users#get_email"
  get "user/ics_url",                            to: "users#get_ics_url"
  get "user/oauth_credentials",                  to: "users#list_oauth_credentials"
  delete "user/oauth_credentials/:credential_id", to: "users#disconnect_oauth_credential"
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

  post "user/is_processed",      to: "users#is_processed"
  post "user/processed_events",  to: "users#get_processed_events_by_term"

  get "user/extension_config",           to: "user_extension_config#get"
  put "user/extension_config",           to: "user_extension_config#set"

  get "user/flag_enabled",              to: "users#flag_is_enabled"
  get "user/feature_flags",             to: "users#feature_flags"

  get  "user/notifications_status",     to: "users#notifications_status"
  post "user/notifications/disable",    to: "users#disable_notifications"
  post "user/notifications/enable",     to: "users#enable_notifications"

  # Friends system
  get    "friends",                                   to: "friends#index"
  get    "friends/meetings",                          to: "friend_meetings#index"
  post   "friends/meetings",                          to: "friend_meetings#create"
  get    "friends/meetings/:id",                      to: "friend_meetings#show"
  patch  "friends/meetings/:id",                      to: "friend_meetings#update"
  delete "friends/meetings/:id",                      to: "friend_meetings#destroy"
  delete "friends/meetings/:id/attendance",           to: "friend_meetings#leave"
  get    "friends/requests",                          to: "friends#requests"
  post   "friends/requests",                          to: "friends#create_request"
  post   "friends/requests/:request_id/accept",       to: "friends#accept"
  post   "friends/requests/:request_id/decline",      to: "friends#decline"
  delete "friends/requests/:request_id",              to: "friends#cancel_request"
  # Friend groups. Every route answers 404 while the friend_groups flag is off.
  get    "friends/groups",                            to: "friend_groups#index"
  post   "friends/groups",                            to: "friend_groups#create"
  get    "friends/groups/:group_id",                  to: "friend_groups#show"
  patch  "friends/groups/:group_id",                  to: "friend_groups#update"
  delete "friends/groups/:group_id",                  to: "friend_groups#destroy"
  post   "friends/groups/:group_id/members",          to: "friend_groups#add_member"
  delete "friends/groups/:group_id/members/:friend_id", to: "friend_groups#remove_member"
  delete "friends/:friend_id",                        to: "friends#unfriend"
  patch  "friends/:friend_id/expiry",                 to: "friends#update_expiry"
  post   "friends/:friend_id/processed_events",       to: "friends#processed_events"
  post   "friends/:friend_id/is_processed",           to: "friends#is_processed"
  get    "friends/:friend_id/visibility",             to: "friends#visibility"
  patch  "friends/:friend_id/visibility",             to: "friends#update_visibility"
  get    "friends/:friend_id/busy_blocks",            to: "friends#busy_blocks"

  # One-time meeting links for people who are not friends (#652).
  get    "meeting_links",                             to: "meeting_links#index"
  post   "meeting_links",                             to: "meeting_links#create"
  delete "meeting_links/:id",                         to: "meeting_links#destroy"

  get "faculty/by_rmp", to: "faculty#get_info_by_rmp_id"
  get "terms/active",          to: "misc#get_active_terms"
  get "terms/current_and_next", to: "misc#get_current_and_next_terms"

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
  # Legacy path. The published extension still calls it.
  resources :google_calendar_events, only: [] do
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

  match "*path", to: "catch_all#not_found", via: :all
end
