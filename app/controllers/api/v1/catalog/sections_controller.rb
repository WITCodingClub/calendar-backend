# frozen_string_literal: true

module Api
  module V1
    module Catalog
      class SectionsController < Api::V1::PublicController
        # The seat filters echo in meta.filters as booleans.
        def index
          list = list_request(:sections)
          render_collection(list.rows, meta: list.meta.merge(filters: list.filters))
        end

        def show
          render_resource(::Catalog::SectionSerializer.new(::Catalog::SectionQuery.find!(params[:crn], params[:term_uid])).as_json)
        end

        # The list is empty until the course has a vector, which the nightly
        # backfill writes.
        def similar
          course   = ::Catalog::SectionQuery.find!(params[:crn], params[:term_uid])
          sections = ::Catalog::SectionQuery.with_associations(course.similar_sections(limit: similar_limit))

          render_collection(::Catalog::SectionSerializer.collection(sections), meta: { crn: course.crn, limit: similar_limit })
        end
      end
    end
  end
end
