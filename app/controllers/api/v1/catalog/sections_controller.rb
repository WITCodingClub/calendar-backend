# frozen_string_literal: true

module Api
  module V1
    module Catalog
      # GET /api/v1/catalog/sections
      # GET /api/v1/catalog/sections/:crn
      class SectionsController < Api::V1::PublicController
        def index
          page, per_page = pagination

          relation = ::Catalog::SectionQuery.new.call(**filters)
          total    = relation.count("DISTINCT courses.id")
          sections = ::Catalog::SectionQuery
                     .with_associations(relation)
                     .page(page).per(per_page)

          render_collection(
            sections.map { |course| ::Catalog::SectionSerializer.new(course).as_json },
            meta: {
              page:        page,
              per_page:    per_page,
              total_count: total,
              total_pages: (total.to_f / per_page).ceil,
              filters:     filters.compact
            }
          )
        end

        def show
          relation = ::Catalog::SectionQuery.new.call(
            crns:              [ params[:crn] ],
            term_uid:          params[:term_uid],
            include_cancelled: true
          )
          course = ::Catalog::SectionQuery.with_associations(relation).first
          raise ActiveRecord::RecordNotFound, "No section with CRN #{params[:crn]}" if course.nil?

          render_resource(::Catalog::SectionSerializer.new(course).as_json)
        end

        private

        def filters
          {
            term_uid:          params[:term_uid],
            subject:           array_param(:subject),
            course_number:     array_param(:course_number),
            crns:              array_param(:crn),
            pub_ids:           array_param(:pub_id),
            q:                 params[:q],
            schedule_types:    array_param(:schedule_type),
            meets_on:          array_param(:meets_on),
            free_days:         array_param(:free_days),
            begins_after:      params[:begins_after],
            ends_before:       params[:ends_before],
            credit_hours:      array_param(:credit_hours),
            instructor:        params[:instructor],
            include_cancelled: params[:include_cancelled]
          }.compact
        end
      end
    end
  end
end
