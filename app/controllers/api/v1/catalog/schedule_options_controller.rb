# frozen_string_literal: true

module Api
  module V1
    module Catalog
      # POST /api/v1/catalog/schedule_options
      # POST /api/v1/catalog/schedule_options/count
      #
      # Builds and ranks schedules for a list of courses, or only counts them.
      # Catalog::ScheduleOptions::Finder has the rules. The body carries the
      # request, so the edge cache of the GET routes does not apply, and the
      # response gets no public cache headers.
      #
      # The schedule_builder flag gates both routes: 404 while it is off. The
      # route is public, so the flag is on when it is on for everyone, or when
      # the request has a valid token and the flag is on for that user. A bad
      # token is the same as no token. Apart from that 404, the answer is the
      # same for every caller.
      #
      # When every search slot is in use (Catalog::ScheduleOptions::Slots),
      # the answer is 503 SCHEDULE_BUILDER_BUSY with Retry-After: 1 and
      # retry_after in the body, the same as a 429.
      class ScheduleOptionsController < Api::V1::PublicController
        BUSY_RETRY_AFTER = 1

        before_action :require_schedule_builder

        rescue_from ::Catalog::ScheduleOptions::BusyError, with: :render_busy

        def create
          render json: { data: finder.call }
        end

        def count
          render json: { data: finder.count }
        end

        private

        def finder
          ::Catalog::ScheduleOptions::Finder.new(params.to_unsafe_h.slice("term_uid", "courses", "preferences", "limit"))
        end

        def require_schedule_builder
          return if Flipper.enabled?(FeatureFlags::SCHEDULE_BUILDER)
          return if (user = optional_token_user) && Flipper.enabled?(FeatureFlags::SCHEDULE_BUILDER, user)

          render_error "The schedule builder is not enabled", status: :not_found
        end

        def render_busy(exception)
          response.headers["Retry-After"] = BUSY_RETRY_AFTER.to_s
          render_error exception.message, status: :service_unavailable, code: "SCHEDULE_BUILDER_BUSY",
                                          retry_after: BUSY_RETRY_AFTER
        end
      end
    end
  end
end
