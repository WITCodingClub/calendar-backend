# frozen_string_literal: true

module Api
  module V1
    module Catalog
      # GET /api/v1/catalog/programs
      # GET /api/v1/catalog/programs/:slug
      #
      # Degree programs from the academic catalog, for one catalog year
      # (docs/degree-requirements.md). Without catalog_year, the newest
      # imported year.
      class ProgramsController < Api::V1::PublicController
        def index
          catalog_year = find_catalog_year
          programs = query.call(catalog_year: catalog_year, kind: array_param(:kind), level: array_param(:level), q: params[:q]).to_a

          render_collection(
            programs.map { |set| ::Catalog::ProgramSerializer.summary(set) },
            meta: { count: programs.size, catalog_year: catalog_year.name, catalog_years: query.catalog_years.map(&:name) }
          )
        end

        def show
          catalog_year = find_catalog_year
          set = query.find(params[:slug], catalog_year: catalog_year)
          raise ActiveRecord::RecordNotFound, "No program #{params[:slug]} in the #{catalog_year.name} catalog" if set.nil?

          render_resource(::Catalog::ProgramSerializer.new(set).as_json)
        end

        private

        def query = @query ||= ::Catalog::ProgramQuery.new

        def find_catalog_year
          catalog_year = query.catalog_year(params[:catalog_year])
          return catalog_year if catalog_year

          raise ActiveRecord::RecordNotFound,
                params[:catalog_year].present? ? "No catalog year #{params[:catalog_year]}" : "No catalog year is imported"
        end
      end
    end
  end
end
