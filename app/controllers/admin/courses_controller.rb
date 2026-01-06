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

    def manual_add
      authorize Course
      @users = User.order(:email)
    end

    def process_manual_add
      authorize Course

      begin
        # Parse the JSON input
        courses_data = JSON.parse(params[:courses_json])

        # Validate it's an array
        unless courses_data.is_a?(Array)
          flash[:error] = "Invalid JSON format. Expected an array of course objects."
          return redirect_to manual_add_admin_courses_path
        end

        # Find the user
        user = User.find(params[:user_id])

        # Process the courses using CourseProcessorService
        result = CourseProcessorService.new(courses_data, user).call

        flash[:success] = "Successfully processed #{result.count} courses for #{user.email}"
        redirect_to admin_user_path(user)
      rescue JSON::ParserError => e
        flash[:error] = "Invalid JSON format: #{e.message}"
        redirect_to manual_add_admin_courses_path
      rescue ActiveRecord::RecordNotFound
        flash[:error] = "User not found"
        redirect_to manual_add_admin_courses_path
      rescue => e
        flash[:error] = "Error processing courses: #{e.message}"
        redirect_to manual_add_admin_courses_path
      end
    end

  end
end
