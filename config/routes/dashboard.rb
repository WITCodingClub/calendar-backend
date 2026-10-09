# frozen_string_literal: true

# The user dashboard. Any signed-in user.

# User dashboard (session-authenticated, any signed-in user)
authenticate :user do
  namespace :dashboard do
    root to: "overview#index"
    resource  :onboarding,           only: [ :show ], controller: "onboarding"
    resource  :schedule,             only: [ :show ]
    resources :calendar_preferences, only: [ :index, :update ] do
      patch :university_events, on: :collection
    end
    resources :connected_accounts,   only: [ :index, :destroy ] do
      member { patch :calendar_placement }
    end
    resources :sign_in_identities,   only: [ :destroy ]
    resource  :ics_feed,             only: [ :show ]
    resource  :notifications,        only: [ :show, :update ] do
      patch :university_events
    end
    # Before resources :friends, so "groups" is not read as a friend id.
    resources :friend_groups, path: "friends/groups", only: [ :create, :update, :destroy ] do
      resources :members, controller: "friend_group_members", only: [ :create, :destroy ]
    end
    resources :friends, only: [ :index, :show, :create, :destroy ] do
      member     { post :accept; post :decline; patch :visibility; patch :expiry; post :accept_expiry; post :decline_expiry }
      collection { get :requests }
    end
    resources :meeting_links, only: [ :index, :create, :destroy ]
    resource :settings, only: [ :show ]
  end
end
