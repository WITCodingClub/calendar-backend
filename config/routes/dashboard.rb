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
    resources :connected_apps,       only: [ :destroy ]
    resource  :ics_feed,             only: [ :show ]
    resource  :notifications,        only: [ :show, :update ] do
      patch :university_events
      patch :emails
    end
    # Before resources :friends, so "groups" is not read as a friend id.
    resources :friend_groups, path: "friends/groups", only: [ :create, :update, :destroy ] do
      resources :members, controller: "friend_group_members", only: [ :create, :destroy ]
    end
    # Hides a group that a friend shared with the user, or opts out of it.
    resources :shared_friend_groups, path: "friends/shared_groups", only: [ :update ]
    # Before resources :friends, so "requests" is not read as a friend id.
    # FriendshipMailer and the extension link to GET /dashboard/friends/requests,
    # so that path must not change.
    namespace :friends do
      # update accepts an incoming request. destroy declines it.
      resources :requests, only: [ :index, :update, :destroy ]
    end
    resources :friends, only: [ :index, :show, :create, :destroy ] do
      scope module: :friends do
        resource :visibility,      only: [ :update ]
        resource :expiry,          only: [ :update ]
        # update accepts the friend's proposal. destroy declines or withdraws it.
        resource :expiry_proposal, only: [ :update, :destroy ]
      end
    end
    resources :meeting_links, only: [ :index, :create, :destroy ]
    resource :settings, only: [ :show ]

    # My programs (#867): the programs from LeopardWeb, the plan of each,
    # profile corrections, planned programs and pathways, and ended programs. Before
    # resources :programs, so "profile", "planned", and "pathways" are not
    # read as a program id.
    resource  :academic_profile, path: "programs/profile", only: [ :edit, :update ]
    resources :planned_programs, path: "programs/planned", only: [ :create, :destroy ]
    # A 3+1, 4+1, or 5-year pathway. The id is the pathway slug.
    resources :planned_pathways, path: "programs/pathways", only: [ :create, :destroy ], constraints: { id: %r{[^/]+} }
    resources :programs, only: [ :index ] do
      member { patch :plan }
    end

    # Read-only catalog pages (#797): the data of the public catalog API, for
    # any signed-in user. A course code in a path has no space ("COMP2350").
    resources :courses,     only: [ :index, :show ], param: :code
    resources :instructors, only: [ :index, :show ]
    resources :finals,      only: [ :index ]
    resources :university_events, path: "events", only: [ :index ]
  end
end
