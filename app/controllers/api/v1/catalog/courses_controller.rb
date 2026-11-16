# frozen_string_literal: true

module Api
  module V1
    module Catalog
      # Courses, not sections: one record for COMP 2350 across every term,
      # with Banner's description and prerequisites (Catalog::CourseDetailsSync).
      class CoursesController < Api::V1::PublicController
        def index
          page     = page_for(:courses)
          relation = ::Catalog::CourseQuery.new.call(q: params[:q], subject: array_param(:subject), term_uid: params[:term_uid])

          render_collection(page.of(relation).map { |course| ::Catalog::CourseSerializer.summary(course) }, meta: page.meta(relation.count))
        end

        def show
          course = ::Catalog::CourseQuery.new.find(params[:code])
          raise ActiveRecord::RecordNotFound, "No course #{params[:code]}" if course.nil?

          render_resource(::Catalog::CourseSerializer.new(course, term: optional_term).as_json)
        end
      end
    end
  end
end
