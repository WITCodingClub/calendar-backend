# frozen_string_literal: true

module Admin
  class FacultiesController < Admin::ApplicationController
    def index
      @faculties = policy_scope(Faculty).order(:last_name, :first_name)

      if params[:search].present?
        search_term = "%#{params[:search]}%"
        @faculties = @faculties.where(
          "first_name ILIKE :q OR last_name ILIKE :q OR display_name ILIKE :q OR email ILIKE :q OR department ILIKE :q OR title ILIKE :q",
          q: search_term
        )
      end

      @faculties = @faculties.page(params[:page]).per(15)
    end

    def show
      @faculty = Faculty.find(params[:id])
      authorize @faculty

      # Get courses grouped by term, ordered by most recent first
      @courses_by_term = @faculty.courses
                                 .includes(:term, meeting_times: { room: :building })
                                 .joins(:term)
                                 .order("terms.year DESC, terms.season DESC")
                                 .group_by(&:term)

      # Get RMP ratings if available
      @rmp_ratings = @faculty.rmp_ratings.order(created_at: :desc) if @faculty.rmp_id.present?
    end

    def missing_rmp_ids
      # Only show faculty with courses - staff without courses don't need RMP data
      @faculties = policy_scope(Faculty).with_courses.where(rmp_id: nil).order(:last_name, :first_name)

      if params[:search].present?
        @faculties = @faculties.where("first_name ILIKE ? OR last_name ILIKE ?", "%#{params[:search]}%", "%#{params[:search]}%")
      end

      @faculties = @faculties.page(params[:page]).per(4)
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
        format.json { render json: { error: e.message }, status: :unprocessable_content }
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
        format.json { render json: { error: e.message }, status: :unprocessable_content }
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
      # Only process faculty with courses - staff without courses don't need RMP data
      missing = Faculty.with_courses.where(rmp_id: nil)

      missing.find_each do |faculty|
        UpdateFacultyRatingsJob.perform_later(faculty.id)
      end

      redirect_to missing_rmp_ids_admin_faculties_path, notice: "Enqueued auto-fill jobs for #{missing.count} faculty members (with courses)"
    end

    def sync_directory
      authorize Faculty

      FacultyDirectorySyncJob.perform_later

      redirect_to admin_faculties_path, notice: "Directory sync started. This may take a few minutes."
    end

    def directory_status
      authorize Faculty

      @last_sync = Faculty.maximum(:directory_last_synced_at)
      @synced_count = Faculty.where.not(directory_last_synced_at: nil).count
      @unsynced_count = Faculty.where(directory_last_synced_at: nil).count
      @total_count = Faculty.count
      @faculty_count = Faculty.faculty_only.count
      @staff_count = Faculty.staff_only.count
    end

  end
end
