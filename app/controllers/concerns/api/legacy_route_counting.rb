# frozen_string_literal: true

module Api
  # Counts the requests to the old paths in config/routes/api/legacy.rb. The
  # count shows in Grafana as calendar_api_legacy_requests_total, by path, so
  # we know when no extension build calls a path any more.
  module LegacyRouteCounting
    extend ActiveSupport::Concern

    included do
      before_action :count_legacy_route, if: -> { request.path_parameters.key?(:legacy_route) }
    end

    private

    def count_legacy_route
      Yabeda.calendar.api_legacy_requests_total.increment({ route: request.path_parameters[:legacy_route] })
    end
  end
end
