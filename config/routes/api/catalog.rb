# frozen_string_literal: true

# The public catalog API: read-only course schedule data, no token.
# docs/public-catalog-api.md documents these paths for outside users, so do
# not change them.
#
# Drawn inside namespace :api in config/routes/api.rb.

# The GraphQL endpoint moved under /api/v1. 308 keeps the method and body.
post "graphql", to: redirect("/api/v1/graphql", status: 308)

namespace :v1 do
  post "graphql", to: "/api/graphql#execute"

  namespace :catalog do
    get "terms",         to: "terms#index"
    get "terms/current", to: "terms#current"
    get "terms/next",    to: "terms#next"
    get "terms/:uid",    to: "terms#show", as: :term, constraints: { uid: /\d+/ }

    get "subjects", to: "subjects#index"

    get "sections",              to: "sections#index"
    get "sections/:crn",         to: "sections#show",    as: :section,          constraints: { crn: /\d+/ }
    get "sections/:crn/similar", to: "sections#similar", as: :similar_sections, constraints: { crn: /\d+/ }

    get "reviews", to: "reviews#index"

    get "instructors",                 to: "instructors#index"
    get "instructors/:pub_id",         to: "instructors#show",    as: :instructor
    get "instructors/:pub_id/similar", to: "instructors#similar", as: :similar_instructors
  end
end
