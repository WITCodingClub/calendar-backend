# frozen_string_literal: true

module Api
  module V1
    module Catalog
      class SectionsController < Api::V1::PublicController
        def index
          page     = page_for(:sections)
          relation = ::Catalog::SectionQuery.new.call(**filters)
          total    = relation.count("DISTINCT courses.id")
          sections = page.of(::Catalog::SectionQuery.with_associations(relation))

          render_collection(::Catalog::SectionSerializer.collection(sections), meta: page.meta(total).merge(filters: filters))
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

        private

        def filters
          @filters ||= {
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
            include_cancelled: params[:include_cancelled],
            # The seat filters echo in meta.filters as booleans.
            open_only:         ::Catalog::Params.strict_boolean(params[:open_only], :open_only),
            include_waitlist:  ::Catalog::Params.strict_boolean(params[:include_waitlist], :include_waitlist)
          }.compact
        end
      end
    end
  end
end
