# frozen_string_literal: true

module Admin
  class CoursesController < Admin::ApplicationController
    def index
      authorize Course
      @courses = policy_scope(Course).includes(:term, :faculties).order(created_at: :desc)

      @courses = search_scope(@courses, "courses.title", "courses.subject")

      @courses = @courses.where(term_id: params[:term_id]) if params[:term_id].present?
      @courses = @courses.page(params[:page]).per(25)
      @terms   = Term.reverse_chronological
    end

    def show
      @course = Course.find_by_public_id!(params[:id]) # rubocop:disable Rails/DynamicFindBy
      authorize @course
    end
  end
end
