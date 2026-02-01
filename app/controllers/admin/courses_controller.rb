# frozen_string_literal: true

module Admin
  class CoursesController < Admin::ApplicationController
    def index
      @courses = policy_scope(Course).includes(:term, :faculties).order(created_at: :desc)

      if params[:search].present?
        @courses = @courses.where("title ILIKE ? OR subject ILIKE ?", "%#{params[:search]}%", "%#{params[:search]}%")
      end

      @courses = @courses.page(params[:page]).per(6)
    end

    def show
      @course = Course.find_by_public_id!(params[:id]) # rubocop:disable Rails/DynamicFindBy
      authorize @course
    end

  end
end
