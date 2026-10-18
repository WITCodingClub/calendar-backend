# frozen_string_literal: true

module Api
  module V1
    module Catalog
      # GET /api/v1/catalog/courses
      # GET /api/v1/catalog/courses/:code
      #
      # Courses, not sections: one record for COMP 2350 across every term,
      # with Banner's description and prerequisites (Catalog::CourseDetailsSync).
      class CoursesController < Api::V1::PublicController
        def index
          page, per_page = course_pagination

          relation = ::Catalog::CourseQuery.new.call(q: params[:q], subject: array_param(:subject), term_uid: params[:term_uid])
          total    = relation.count

          render_collection(
            relation.page(page).per(per_page).map { |course| ::Catalog::CourseSerializer.summary(course) },
            meta: { page: page, per_page: per_page, total_count: total, total_pages: (total.to_f / per_page).ceil }
          )
        end

        def show
          course = ::Catalog::CourseQuery.new.find(params[:code])
          raise ActiveRecord::RecordNotFound, "No course #{params[:code]}" if course.nil?

          render_resource(::Catalog::CourseSerializer.new(course, term: find_term_param).as_json)
        end

        private

        def course_pagination
          page     = [ params[:page].to_i, 1 ].max
          per_page = (params[:per_page].presence&.to_i || ::Catalog::CourseQuery::DEFAULT_PER_PAGE)
                     .clamp(1, ::Catalog::CourseQuery::MAX_PER_PAGE)
          [ page, per_page ]
        end

        def find_term_param
          return nil if params[:term_uid].blank?

          Term.find_by(uid: params[:term_uid]) || raise(ActiveRecord::RecordNotFound, "No term #{params[:term_uid]}")
        end
      end
    end
  end
end
