# frozen_string_literal: true

module Api
  module V1
    module Catalog
      # Degree programs from the academic catalog, for one catalog year
      # (docs/degree-requirements.md). Without catalog_year, the newest
      # imported year.
      class ProgramsController < Api::V1::PublicController
        rescue_from ::Catalog::ProgramQuery::NotFoundError, with: :render_not_found

        def index
          catalog_year = query.catalog_year!(params[:catalog_year])
          programs = query.call(catalog_year: catalog_year, kind: array_param(:kind), level: array_param(:level), q: params[:q],
                                parent: params[:parent_program]).to_a

          render_collection(
            programs.map { |set| ::Catalog::ProgramSerializer.summary(set) },
            meta: { count: programs.size, catalog_year: catalog_year.name, catalog_years: query.catalog_years.map(&:name) }
          )
        end

        def show
          catalog_year = query.catalog_year!(params[:catalog_year])
          set = query.find!(params[:slug], catalog_year: catalog_year)
          render_resource(::Catalog::ProgramSerializer.new(set).as_json)
        end

        private

        def query = @query ||= ::Catalog::ProgramQuery.new
      end
    end
  end
end
