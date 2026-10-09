# frozen_string_literal: true

# The admin area, and the fallback for people who are not admins.

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
        # Ending sessions for an account someone reports as compromised.
        delete "sessions/:session_id",
               to: "users#revoke_session",
               as: :revoke_session
        delete "sessions",
               to: "users#revoke_all_sessions",
               as: :revoke_all_sessions
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
    resources :calendar_events,             only: [ :index ]

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

    # These tools can run jobs, change flags, read any row, or show console
    # sessions, so they need a super admin. Other admins get the fallback
    # below, which sends them away.
    constraints SuperAdminConstraint.new do
      mount MissionControl::Jobs::Engine, at: "jobs"
      mount Flipper::UI.app(Flipper) { |builder| builder.use FeatureFlags::UserActorAdapter::UnknownActorRedirect }, at: "flipper"
      mount Blazer::Engine,               at: "blazer"
      mount PgHero::Engine,               at: "pghero"
      mount Audits1984::Engine,           at: "audits"
    end
  end
end

# Fallback if AdminConstraint fails
get "admin",       to: "application#admin_unauthorized"
get "admin/*path", to: "application#admin_unauthorized"
