# frozen_string_literal: true

module Admin
  class FinalsSchedulesController < Admin::ApplicationController
    before_action :set_finals_schedule, only: [:show, :destroy, :confirm_replace, :process_schedule]

    def index
      @finals_schedules = policy_scope(FinalsSchedule)
                          .includes(:term, :uploaded_by)
                          .recent

      if params[:term_id].present?
        @finals_schedules = @finals_schedules.for_term(Term.find(params[:term_id]))
      end

      @finals_schedules = @finals_schedules.page(params[:page]).per(10)
      @terms = available_terms
    end

    def show
      authorize @finals_schedule

      # Load associated final exams for this term
      @final_exams = FinalExam.where(term: @finals_schedule.term)
                              .includes(course: :faculties)
                              .order(:exam_date, :start_time)
    end

    def new
      @finals_schedule = FinalsSchedule.new
      authorize @finals_schedule
      @terms = available_terms
    end

    def create
      @finals_schedule = FinalsSchedule.new(term_id: params.dig(:finals_schedule, :term_id))
      @finals_schedule.uploaded_by = current_user
      authorize @finals_schedule

      # Attach PDF with conventional filename
      attach_pdf_with_conventional_name(@finals_schedule)

      unless @finals_schedule.save
        @terms = available_terms
        render :new, status: :unprocessable_content
        return
      end

      # Check if there are existing exams for this term
      existing_exams = FinalExam.where(term_id: @finals_schedule.term_id)

      if existing_exams.any?
        # Redirect to confirmation page - file is already saved
        redirect_to confirm_replace_admin_finals_schedule_path(@finals_schedule)
      else
        # No existing exams, process immediately
        FinalsScheduleProcessJob.perform_later(@finals_schedule)
        redirect_to admin_finals_schedule_path(@finals_schedule),
                    notice: "Finals schedule uploaded successfully. Processing has started."
      end
    end

    def confirm_replace
      authorize @finals_schedule

      @existing_exams = FinalExam.where(term_id: @finals_schedule.term_id)
                                 .includes(course: :faculties)
                                 .order(:exam_date, :start_time)
    end

    def process_schedule
      authorize @finals_schedule

      # Queue background job to process the PDF
      FinalsScheduleProcessJob.perform_later(@finals_schedule)
      redirect_to admin_finals_schedule_path(@finals_schedule),
                  notice: "Finals schedule processing has started. Existing exams will be updated."
    end

    def destroy
      authorize @finals_schedule

      term = @finals_schedule.term
      @finals_schedule.destroy

      redirect_to admin_finals_schedules_path,
                  notice: "Finals schedule for #{term.name} was successfully deleted."
    end

    private

    def set_finals_schedule
      @finals_schedule = FinalsSchedule.find(params[:id])
    end

    def finals_schedule_params
      params.expect(finals_schedule: [:term_id, :pdf_file])
    end

    # Attach PDF file with conventional filename: {term_uid}-finals-schedule-{timestamp}.pdf
    def attach_pdf_with_conventional_name(finals_schedule)
      uploaded_file = params.dig(:finals_schedule, :pdf_file)
      return if uploaded_file.blank?

      term = Term.find_by(id: finals_schedule.term_id)

      if term
        timestamp = Time.current.strftime("%Y%m%d-%H%M%S")
        new_filename = "#{term.uid}-finals-schedule-#{timestamp}.pdf"

        finals_schedule.pdf_file.attach(
          io: uploaded_file.tempfile,
          filename: new_filename,
          content_type: uploaded_file.content_type
        )
      else
        # Fall back to original filename if term not found
        finals_schedule.pdf_file.attach(uploaded_file)
      end
    end

    # Returns terms available for finals schedule upload
    # By default, only current and future terms are shown
    # Enable :finals_retroactive feature flag to show all terms (for historical imports)
    def available_terms
      if Flipper.enabled?(FlipperFlags::FINALS_RETROACTIVE, current_user)
        Term.order(year: :desc, season: :desc)
      else
        Term.current_and_future
      end
    end

  end
end
