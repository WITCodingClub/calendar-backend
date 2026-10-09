# frozen_string_literal: true

module Admin
  class FacultiesController < Admin::ApplicationController
    def index
      authorize Faculty
      @faculties = policy_scope(Faculty).order(:last_name, :first_name)

      if params[:search].present?
        q = "%#{params[:search]}%"
        @faculties = @faculties.where(
          "first_name ILIKE :q OR last_name ILIKE :q OR display_name ILIKE :q OR email ILIKE :q OR department ILIKE :q OR title ILIKE :q",
          q: q
        )
      end

      @faculties = @faculties.where(employee_type: params[:employee_type]) if params[:employee_type].present?
      @faculties = @faculties.page(params[:page]).per(25)

      @stats = {
        total:   Faculty.count,
        faculty: Faculty.faculty_only.count,
        staff:   Faculty.staff_only.count,
        synced:  Faculty.where.not(directory_last_synced_at: nil).count
      }
    end

    def show
      @faculty = Faculty.find(params[:id])
      authorize @faculty

      @courses_by_term = @faculty.courses
                                 .includes(:term, meeting_times: { rooms: :building })
                                 .joins(:term)
                                 .order("terms.year DESC, terms.season DESC")
                                 .group_by(&:term)

      @course_count = @courses_by_term.values.sum(&:size)
      @rmp_ratings = @faculty.rmp_ratings.order(created_at: :desc) if @faculty.rmp_id.present?
    end

    def missing_rmp_ids
      authorize Faculty, :missing_rmp_ids?
      @faculties = policy_scope(Faculty).with_courses.where(rmp_id: nil).order(:last_name, :first_name)

      if params[:search].present?
        @faculties = @faculties.where("first_name ILIKE ? OR last_name ILIKE ?", "%#{params[:search]}%", "%#{params[:search]}%")
      end

      @faculties = @faculties.page(params[:page]).per(25)
      # One grouped count for the page, not one count for each row (#689).
      @course_counts = CourseFaculty.where(faculty_id: @faculties.map(&:id)).group(:faculty_id).count
    end

    def search_rmp
      @faculty = Faculty.find(params[:id])
      authorize @faculty
      service = Faculties::RateMyProfessorClient.new

      search_result = service.search_professors(@faculty.full_name, count: 10)
      @teachers = search_result.dig("data", "newSearch", "teachers", "edges") || []

      respond_to do |format|
        format.html
        format.json { render json: { teachers: @teachers } }
      end
    rescue => e
      Rails.error.report(e, handled: true, context: { faculty_id: params[:id] })
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
      Faculties::UpdateRatingsJob.perform_later(@faculty.id)

      respond_to do |format|
        format.html { redirect_to missing_rmp_ids_admin_faculties_path, notice: "RMP ID assigned. Fetching ratings in background..." }
        format.json { render json: { success: true } }
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

      Faculties::UpdateRatingsJob.perform_later(@faculty.id)

      respond_to do |format|
        format.html { redirect_to missing_rmp_ids_admin_faculties_path, notice: "Searching for #{@faculty.full_name} on Rate My Professor..." }
        format.json { render json: { success: true } }
      end
    end

    def batch_auto_fill
      authorize Faculty
      missing = Faculty.with_courses.where(rmp_id: nil)
      missing.find_each { |f| Faculties::UpdateRatingsJob.perform_later(f.id) }
      redirect_to missing_rmp_ids_admin_faculties_path, notice: "Enqueued auto-fill jobs for #{missing.count} faculty members"
    end

    def sync_directory
      authorize Faculty
      Faculties::DirectorySyncJob.perform_later
      redirect_to admin_faculties_path, notice: "Directory sync started. This may take a few minutes."
    end

    def directory_status
      authorize Faculty

      @last_sync     = Faculty.maximum(:directory_last_synced_at)
      @synced_count  = Faculty.where.not(directory_last_synced_at: nil).count
      @unsynced_count = Faculty.where(directory_last_synced_at: nil).count
      @total_count   = Faculty.count
      @faculty_count = Faculty.faculty_only.count
      @staff_count   = Faculty.staff_only.count
    end
  end
end
