# frozen_string_literal: true

module Admin
  class CoursesController < Admin::ApplicationController
    def index
      @courses = policy_scope(Course).includes(:term, :faculty).order(created_at: :desc).page(params[:page])
    end
  end
end
