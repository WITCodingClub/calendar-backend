# frozen_string_literal: true

module Api
  module V1
    module Catalog
      # GET /api/v1/catalog/instructors
      # GET /api/v1/catalog/instructors/:pub_id
      # GET /api/v1/catalog/instructors/:pub_id/similar
      class InstructorsController < Api::V1::PublicController
        def index
          page, per_page = pagination

          scope = ::Catalog::InstructorQuery.new.call(
            term_uid: params[:term_uid], q: params[:q], semantic: boolean_param(:semantic)
          )

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

        # The full record: Rate My Professors distribution, tags, and recent
        # reviews. With term_uid, also the sections taught in that term.
        def show
          term = find_term_param
          render_resource(::Catalog::InstructorDetailSerializer.new(find_instructor, term: term).as_json)
        end

        # Instructors who teach something close to what this one teaches. The
        # list is empty until the instructor has a vector, which the nightly
        # backfill writes.
        def similar
          faculty = find_instructor
          people  = faculty.similar_instructors(limit: similar_limit).includes(:rating_distribution)

          render_collection(
            people.map { |person| ::Catalog::InstructorSerializer.new(person).as_json },
            meta: { pub_id: faculty.public_id, limit: similar_limit }
          )
        end

        private

        def find_term_param
          return nil if params[:term_uid].blank?

          Term.find_by(uid: params[:term_uid]) || raise(ActiveRecord::RecordNotFound, "No term #{params[:term_uid]}")
        end

        def find_instructor
          faculty = Faculty.includes(:rating_distribution).find_by_public_id(params[:pub_id])
          raise ActiveRecord::RecordNotFound, "No instructor #{params[:pub_id]}" if faculty.nil?

          faculty
        end

        def similar_limit
          @similar_limit ||= (params[:limit].presence&.to_i || Embeddable::DEFAULT_SIMILAR_LIMIT)
                            .clamp(1, Embeddable::MAX_SIMILAR_LIMIT)
        end
      end
    end
  end
end
