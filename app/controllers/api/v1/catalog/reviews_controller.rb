# frozen_string_literal: true

module Api
  module V1
    module Catalog
      # Rate My Professors reviews of WIT instructors. `semantic=true` ranks
      # them by meaning, so "lots of group projects" finds the reviews that say
      # so in other words.
      class ReviewsController < Api::V1::PublicController
        def index
          page     = page_for(:reviews)
          relation = ::Catalog::ReviewQuery.new.call(**filters)
          reviews  = page.of(::Catalog::ReviewQuery.with_associations(relation))

          render_collection(
            reviews.map { |review| ::Catalog::ReviewSerializer.new(review).as_json },
            meta: page.meta(relation.count).merge(filters: filters, source: ::Catalog::ReviewSerializer::SOURCE)
          )
        end

        private

        def filters
          @filters ||= { instructor: params[:instructor], q: params[:q], semantic: params[:semantic], sentiment: params[:sentiment] }.compact
        end
      end
    end
  end
end
