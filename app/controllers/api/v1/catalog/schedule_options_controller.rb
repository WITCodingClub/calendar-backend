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
      class ScheduleOptionsController < Api::V1::PublicController
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
      end
    end
  end
end
