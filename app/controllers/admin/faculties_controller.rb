# frozen_string_literal: true

module Admin
  class FacultiesController < Admin::ApplicationController
    def index
      @faculties = policy_scope(Faculty).order(:last_name, :first_name).page(params[:page])
    end

    def missing_rmp_ids
      @faculties = policy_scope(Faculty).where(rmp_id: nil).order(:last_name, :first_name).page(params[:page])
    end

    def search_rmp
      @faculty = Faculty.find(params[:id])
      authorize @faculty
      service = RateMyProfessorService.new

      search_result = service.search_professors(@faculty.full_name, count: 10)
      @teachers = search_result.dig("data", "newSearch", "teachers", "edges") || []

      respond_to do |format|
        format.html
        format.json { render json: { teachers: @teachers } }
      end
    rescue => e
      respond_to do |format|
        format.html { redirect_to missing_rmp_ids_admin_faculties_path, alert: "Error searching: #{e.message}" }
        format.json { render json: { error: e.message }, status: :unprocessable_entity }
      end
    end

    def assign_rmp_id
      @faculty = Faculty.find(params[:id])
      authorize @faculty

      rmp_id = params[:rmp_id]

      if rmp_id.blank?
        flash[:alert] = "RMP ID cannot be blank"
        redirect_to missing_rmp_ids_admin_faculties_path
        return
      end

      @faculty.update!(rmp_id: rmp_id)

      # Enqueue job to fetch ratings
      UpdateFacultyRatingsJob.perform_later(@faculty.id)

      respond_to do |format|
        format.html { redirect_to missing_rmp_ids_admin_faculties_path, notice: "RMP ID assigned successfully. Fetching ratings in background..." }
        format.json { render json: { success: true, message: "RMP ID assigned successfully" } }
      end
    rescue ActiveRecord::RecordInvalid => e
      respond_to do |format|
        format.html { redirect_to missing_rmp_ids_admin_faculties_path, alert: "Error: #{e.message}" }
        format.json { render json: { error: e.message }, status: :unprocessable_entity }
      end
    end

    def auto_fill_rmp_id
      @faculty = Faculty.find(params[:id])
      authorize @faculty

      # Use the existing job to search and link
      UpdateFacultyRatingsJob.perform_later(@faculty.id)

      respond_to do |format|
        format.html { redirect_to missing_rmp_ids_admin_faculties_path, notice: "Searching for #{@faculty.full_name} on Rate My Professor..." }
        format.json { render json: { success: true, message: "Search started" } }
      end
    end

    def batch_auto_fill
      authorize Faculty
      missing = Faculty.where(rmp_id: nil)

      missing.find_each do |faculty|
        UpdateFacultyRatingsJob.perform_later(faculty.id)
      end

      redirect_to missing_rmp_ids_admin_faculties_path, notice: "Enqueued auto-fill jobs for #{missing.count} faculty members"
    end

  end
end
