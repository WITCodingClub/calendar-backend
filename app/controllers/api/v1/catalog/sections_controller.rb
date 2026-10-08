# frozen_string_literal: true

module Api
  module V1
    module Catalog
      # GET /api/v1/catalog/sections
      # GET /api/v1/catalog/sections/:crn
      # GET /api/v1/catalog/sections/:crn/similar
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
          course = find_section(params[:crn], params[:term_uid], with_associations: true)

          render_resource(::Catalog::SectionSerializer.new(course).as_json)
        end

        # Sections that teach something close to this one. The list is empty
        # until the section has a vector, which the nightly backfill writes.
        def similar
          course   = find_section(params[:crn], params[:term_uid])
          relation = ::Catalog::SectionQuery.with_associations(course.similar_sections(limit: similar_limit))

          render_collection(
            relation.map { |section| ::Catalog::SectionSerializer.new(section).as_json },
            meta: { crn: course.crn, limit: similar_limit }
          )
        end

        private

        def find_section(crn, term_uid, with_associations: false)
          relation = ::Catalog::SectionQuery.new.call(
            crns:              [ crn ],
            term_uid:          term_uid,
            include_cancelled: true
          )
          relation = ::Catalog::SectionQuery.with_associations(relation) if with_associations

          relation.first || raise(ActiveRecord::RecordNotFound, "No section with CRN #{crn}")
        end

        def similar_limit
          @similar_limit ||= (params[:limit].presence&.to_i || Embeddable::DEFAULT_SIMILAR_LIMIT)
                            .clamp(1, Embeddable::MAX_SIMILAR_LIMIT)
        end

        def filters
          {
            term_uid:          params[:term_uid],
            subject:           array_param(:subject),
            course_number:     array_param(:course_number),
            crns:              array_param(:crn),
            pub_ids:           array_param(:pub_id),
            q:                 params[:q],
            semantic:          params[:semantic],
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
