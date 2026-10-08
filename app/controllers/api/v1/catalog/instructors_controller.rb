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
          people = scope.page(page).per(per_page)

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

        # Ranks by meaning when the caller asks for it, and by the literal
        # words otherwise. A semantic search that cannot reach the API falls
        # back to the name match rather than failing.
        def apply_search(scope)
          return scope.order(:last_name, :first_name) if params[:q].blank?

          ranked = ::Catalog::SemanticSearch.ranked_scope(scope, params[:q]) if boolean_param(:semantic)
          return ranked if ranked

          query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
          scope.where(
            "faculties.first_name ILIKE :q OR faculties.last_name ILIKE :q OR faculties.display_name ILIKE :q",
            q: query
          ).order(:last_name, :first_name)
        end
      end
    end
  end
end
