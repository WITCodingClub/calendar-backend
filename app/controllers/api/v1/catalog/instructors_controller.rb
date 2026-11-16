# frozen_string_literal: true

module Api
  module V1
    module Catalog
      class InstructorsController < Api::V1::PublicController
        def index
          list = list_request(:instructors)
          render_collection(list.rows, meta: list.meta)
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
