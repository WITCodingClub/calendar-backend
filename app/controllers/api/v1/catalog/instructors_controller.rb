# frozen_string_literal: true

module Api
  module V1
    module Catalog
      # GET /api/v1/catalog/instructors
      class InstructorsController < Api::V1::PublicController
        def index
          page, per_page = pagination

          # Subquery rather than joins(:courses): a join would multiply rows by
          # section count and break both the page size and the total.
          scope = Faculty.where(id: Faculty.joins(:courses).select("faculties.id"))
                         .includes(:rating_distribution)
          scope = scope.where(id: faculty_ids_for_term) if params[:term_uid].present?
          scope = apply_search(scope)

          total  = scope.count
          people = scope.order(:last_name, :first_name).page(page).per(per_page)

          render_collection(
            people.map { |faculty| ::Catalog::InstructorSerializer.new(faculty).as_json },
            meta: {
              page:        page,
              per_page:    per_page,
              total_count: total,
              total_pages: (total.to_f / per_page).ceil
            }
          )
        end

        def show
          faculty = Faculty.includes(:rating_distribution).find_by_public_id(params[:pub_id])
          raise ActiveRecord::RecordNotFound, "No instructor #{params[:pub_id]}" if faculty.nil?

          render_resource(::Catalog::InstructorSerializer.new(faculty).as_json)
        end

        private

        def faculty_ids_for_term
          Faculty.joins(:courses)
                 .where(courses: { term_id: Term.where(uid: params[:term_uid].to_i).select(:id) })
                 .select("faculties.id")
        end

        def apply_search(scope)
          return scope if params[:q].blank?

          query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
          scope.where(
            "faculties.first_name ILIKE :q OR faculties.last_name ILIKE :q OR faculties.display_name ILIKE :q",
            q: query
          )
        end
      end
    end
  end
end
