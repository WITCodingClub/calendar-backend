# frozen_string_literal: true

module Directives
  # No published standard defines a rate limit directive. This one publishes
  # the Rack::Attack throttle that covers /api/graphql.
  class RateLimit < GraphQL::Schema::Directive
    graphql_name "rateLimit"
    description "The server accepts at most max requests from one IP address in each window of " \
                "seconds. The GraphQL and REST catalog APIs share this limit. Every response " \
                "sends the RateLimit and RateLimit-Policy headers, and a 429 response sends " \
                "Retry-After."

    locations SCHEMA

    argument :max, Integer, required: true,
             description: "The number of requests allowed in one window."
    argument :window, Integer, required: true,
             description: "The length of the window, in seconds."
  end
end
