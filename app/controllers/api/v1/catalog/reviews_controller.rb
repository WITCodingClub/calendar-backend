# frozen_string_literal: true

module Api
  module V1
    module Catalog
      # GET /api/v1/catalog/reviews
      #
      # Rate My Professors reviews of WIT instructors. `semantic=true` ranks
      # them by meaning, so "lots of group projects" finds the reviews that say
      # so in other words.
      class ReviewsController < Api::V1::PublicController
        def index
          page, per_page = pagination

          relation = ::Catalog::ReviewQuery.new.call(**filters)
          total    = relation.count
          reviews  = ::Catalog::ReviewQuery.with_associations(relation).page(page).per(per_page)

          render_collection(
            reviews.map { |review| ::Catalog::ReviewSerializer.new(review).as_json },
            meta: {
              page:        page,
              per_page:    per_page,
              total_count: total,
              total_pages: (total.to_f / per_page).ceil,
              filters:     filters.compact,
              source:      ::Catalog::ReviewSerializer::SOURCE
            }
          )
        end

        private

        # Reviews are shorter than sections, so they get their own page size.
        def pagination
          page     = [ params[:page].to_i, 1 ].max
          per_page = params[:per_page].presence&.to_i || ::Catalog::ReviewQuery::DEFAULT_PER_PAGE

          [ page, per_page.clamp(1, ::Catalog::ReviewQuery::MAX_PER_PAGE) ]
        end

        def filters
          {
            instructor: params[:instructor],
            q:          params[:q],
            semantic:   params[:semantic],
            sentiment:  params[:sentiment]
          }.compact
        end
      end
    end
  end
end
