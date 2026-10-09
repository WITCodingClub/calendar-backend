# frozen_string_literal: true

# /api/friends: friends, friend requests, groups, and meetings between friends.
# /api/meeting_links: one-time meeting links for people who are not friends.
#
# Drawn inside namespace :api in config/routes/api.rb.

get "friends", to: "friends#index"

scope "friends", as: :friends do
  scope module: :friends do
    get    "meetings",                to: "meetings#index"
    post   "meetings",                to: "meetings#create"
    get    "meetings/:id",            to: "meetings#show"
    patch  "meetings/:id",            to: "meetings#update"
    delete "meetings/:id",            to: "meetings#destroy"
    delete "meetings/:id/attendance", to: "meetings#leave"

    get    "requests",                     to: "requests#index"
    post   "requests",                     to: "requests#create"
    post   "requests/:request_id/accept",  to: "requests#accept"
    post   "requests/:request_id/decline", to: "requests#decline"
    delete "requests/:request_id",         to: "requests#destroy"

    # Every group route answers 404 while the friend_groups flag is off.
    get    "groups",                              to: "groups#index"
    post   "groups",                              to: "groups#create"
    get    "groups/:group_id",                    to: "groups#show"
    patch  "groups/:group_id",                    to: "groups#update"
    delete "groups/:group_id",                    to: "groups#destroy"
    post   "groups/:group_id/members",            to: "groups#add_member"
    delete "groups/:group_id/members/:friend_id", to: "groups#remove_member"
  end

  # After the routes above, so "meetings", "requests", and "groups" are not
  # read as a friend id.
  delete ":friend_id",        to: "friends#destroy"
  patch  ":friend_id/expiry", to: "friends#update_expiry"

  scope module: :friends do
    get   ":friend_id/processed_events",        to: "schedules#processed_events"
    get   ":friend_id/processed_events/status", to: "schedules#processed"
    get   ":friend_id/busy_blocks",             to: "schedules#busy_blocks"
    get   ":friend_id/visibility",              to: "visibilities#show"
    patch ":friend_id/visibility",              to: "visibilities#update"
  end
end

# One-time meeting links (#652). The guest page is /meet/:token in site.rb.
get    "meeting_links",     to: "meeting_links#index"
post   "meeting_links",     to: "meeting_links#create"
delete "meeting_links/:id", to: "meeting_links#destroy"
