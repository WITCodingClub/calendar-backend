# frozen_string_literal: true

module Api
  module V1
    module Catalog
      # Rate My Professors reviews of WIT instructors. `semantic=true` ranks
      # them by meaning, so "lots of group projects" finds the reviews that say
      # so in other words.
      class ReviewsController < Api::V1::PublicController
        def index
          list = list_request(:reviews)
          render_collection(list.rows, meta: list.meta.merge(filters: list.filters))
        end
      end
    end
  end
end
