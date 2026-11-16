# frozen_string_literal: true

module Api
  module V1
    module Catalog
      class InstructorsController < Api::V1::PublicController
        def index
          page  = page_for(:instructors)
          scope = ::Catalog::InstructorQuery.new.call(term_uid: params[:term_uid], q: params[:q], semantic: params[:semantic])

          render_collection(
            page.of(scope).map { |faculty| ::Catalog::InstructorSerializer.new(faculty).as_json },
            meta: page.meta(scope.count)
          )
        end

        # The full record: Rate My Professors distribution, tags, and recent
        # reviews. With term_uid, also the sections taught in that term.
        def show
          term = optional_term
          render_resource(::Catalog::InstructorDetailSerializer.new(::Catalog::InstructorQuery.find!(params[:pub_id]), term: term).as_json)
        end

        # The list is empty until the instructor has a vector, which the
        # nightly backfill writes.
        def similar
          faculty = ::Catalog::InstructorQuery.find!(params[:pub_id])
          people  = faculty.similar_instructors(limit: similar_limit).includes(:rating_distribution)

          render_collection(
            people.map { |person| ::Catalog::InstructorSerializer.new(person).as_json },
            meta: { pub_id: faculty.public_id, limit: similar_limit }
          )
        end
      end
    end
  end
end
