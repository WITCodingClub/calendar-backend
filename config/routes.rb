# frozen_string_literal: true

Rails.application.routes.draw do
  devise_for :users,
             controllers: { sessions: "users/sessions" },
             skip: [ :registrations ]

  get "up" => "rails/health#show", as: :rails_health_check

  get "/session/status", to: "auth_status#show"

  get "/robots.txt", to: "robots#show", format: false

  # Google OAuth2 callback (handles both admin login and calendar OAuth)
  get "/auth/google_oauth2/callback", to: "auth#google"

  # OAuth result pages (opened by Chrome extension)
  get "/oauth/success", to: "oauth#success"
  get "/oauth/failure", to: "oauth#failure"

  # ICS calendar feed (public, token-gated)
  get "/calendar/:calendar_token", to: "calendars#show", as: :calendar, defaults: { format: :ics }

  # Google RISC cross-account protection webhook
  post "/risc/events", to: "risc#create", as: :risc_events

  # API routes (JWT-authenticated)
  namespace :api do
    post "user/onboard",                           to: "users#onboard"
    post "user/gcal",                              to: "users#request_g_cal"
    post "user/gcal/add_email",                    to: "users#add_email_to_g_cal"
    delete "user/gcal/remove_email",               to: "users#remove_email_from_g_cal"
    get "user/id",                                   to: "users#get_id"
    get "user/email",                              to: "users#get_email"
    get "user/ics_url",                            to: "users#get_ics_url"
    get "user/oauth_credentials",                  to: "users#list_oauth_credentials"
    delete "user/oauth_credentials/:credential_id", to: "users#disconnect_oauth_credential"

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
    get    "friends/requests",                          to: "friends#requests"
    post   "friends/requests",                          to: "friends#create_request"
    post   "friends/requests/:request_id/accept",       to: "friends#accept"
    post   "friends/requests/:request_id/decline",      to: "friends#decline"
    delete "friends/requests/:request_id",              to: "friends#cancel_request"
    delete "friends/:friend_id",                        to: "friends#unfriend"
    post   "friends/:friend_id/processed_events",       to: "friends#processed_events"
    post   "friends/:friend_id/is_processed",           to: "friends#is_processed"

    get "faculty/by_rmp", to: "faculty#get_info_by_rmp_id"
    get "terms/active",          to: "misc#get_active_terms"
    get "terms/current_and_next", to: "misc#get_current_and_next_terms"

    # Course processing
    post "process_courses",    to: "courses#process_courses"
    post "courses/reprocess",  to: "courses#reprocess"

    # Calendar preferences (global + per event-type + per university calendar category)
    resources :calendar_preferences, only: [ :index, :show, :update, :destroy ] do
      collection { post :preview }
    end

    # Per-event preferences (meeting time or calendar event)
    resources :meeting_times, only: [] do
      resource :preference, controller: "event_preferences", only: [ :show, :update, :destroy ]
    end
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

  # User dashboard (session-authenticated, any signed-in user)
  authenticate :user do
    namespace :dashboard do
      root to: "overview#index"
      resource  :schedule,             only: [ :show ]
      resources :calendar_preferences, only: [ :index, :update ]
      resources :connected_accounts,   only: [ :index, :destroy ]
      resource  :ics_feed,             only: [ :show ]
      resource  :notifications,        only: [ :show, :update ]
      resources :friends, only: [ :index, :create, :destroy ] do
        member     { post :accept; post :decline }
        collection { get :requests }
      end
      resource :settings, only: [ :show ]
    end
  end

  # Service account OAuth callback (outside namespace so path is /admin/oauth/callback)
  get "/admin/oauth/callback", to: "admin/service_account#callback"

  # Admin area (session-authenticated, AdminConstraint gating)
  constraints AdminConstraint.new do
    namespace :admin do
      root to: "application#index"

      resources :users, only: [ :index, :show, :edit, :update, :destroy ] do
        member do
          delete "oauth_credentials/:credential_id",
                 to: "users#revoke_oauth_credential",
                 as: :revoke_oauth_credential
          post "oauth_credentials/:credential_id/refresh",
               to: "users#refresh_oauth_credential",
               as: :refresh_oauth_credential
          post :force_calendar_sync
          post :add_friend
          delete :remove_friend
        end
      end

      resources :calendars,                   only: [ :index, :destroy ]
      resources :courses,                     only: [ :index, :show ]
      resources :google_calendar_events,      only: [ :index ]

      resources :faculties, only: [ :index, :show ] do
        collection do
          get  :missing_rmp_ids
          post :batch_auto_fill
          post :sync_directory
          get  :directory_status
        end
        member do
          get  :search_rmp
          post :assign_rmp_id
          post :auto_fill_rmp_id
        end
      end

      resources :terms, only: [ :index, :show ]

      resources :finals_schedules, only: [ :index, :new, :create, :show, :destroy ] do
        member do
          get  :confirm_replace
          post :process_schedule
        end
      end

      resources :university_calendar_events, only: [ :index, :show ] do
        collection do
          post :sync
          post :backfill
        end
      end

      resources :rmp_ratings, only: [ :index ]
      resources :rooms,       only: [ :index, :show ]

      get  "course_catalog",                      to: "course_catalog#index",    as: :course_catalog
      post "course_catalog/import/:term_uid",     to: "course_catalog#import",   as: :course_catalog_import
      post "course_catalog/provision/:term_uid",  to: "course_catalog#provision", as: :course_catalog_provision

      resources :buildings, only: [ :index ] do
        collection do
          post :sync
          post :apply_all
        end
        member do
          post :apply_formal_name
        end
      end

      get "navigation",        to: "navigation#index"
      get "lookup/:public_id", to: "public_id_lookup#lookup",   as: :lookup_public_id
      get "go/:public_id",     to: "public_id_lookup#redirect", as: :redirect_public_id

      get  "service_account",           to: "service_account#index",     as: :service_account_index
      get  "service_account/authorize", to: "service_account#authorize", as: :service_account_authorize
      post "service_account/revoke",    to: "service_account#revoke",    as: :service_account_revoke

      mount MissionControl::Jobs::Engine, at: "jobs"
      mount Flipper::UI.app(Flipper),     at: "flipper"
      mount Blazer::Engine,               at: "blazer"
      mount PgHero::Engine,               at: "pghero"
      mount Audits1984::Engine,           at: "audits"
    end
  end

  # Fallback if AdminConstraint fails
  get "admin",       to: "application#admin_unauthorized"
  get "admin/*path", to: "application#admin_unauthorized"

  get "unauthorized", to: "errors#unauthorized"
  get "404",          to: "errors#not_found"
  get "422",          to: "errors#unprocessable_entity"
  get "500",          to: "errors#internal_server_error"

  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end

  root to: "home#index"
end
