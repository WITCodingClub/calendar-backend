# frozen_string_literal: true

module Admin
  class TransferEquivalenciesController < Admin::ApplicationController
    def index
      @equivalencies = policy_scope(Transfer::Equivalency)
                       .includes(transfer_course: :university, wit_course: :term)
                       .order(created_at: :desc)

      if params[:search].present?
        search = "%#{params[:search]}%"
        @equivalencies = @equivalencies.joins(transfer_course: :university)
                                       .where(
                                         "transfer_courses.course_code ILIKE :q OR " \
                                         "transfer_courses.course_title ILIKE :q OR " \
                                         "transfer_universities.name ILIKE :q",
                                         q: search
                                       )
      end

      if params[:university].present?
        @equivalencies = @equivalencies.joins(transfer_course: :university)
                                       .where(transfer_universities: { id: params[:university] })
      end

      @stats = {
        universities: Transfer::University.count,
        transfer_courses: Transfer::Course.count,
        equivalencies: Transfer::Equivalency.count,
        active_equivalencies: Transfer::Equivalency.active.count
      }

      @universities = Transfer::University.order(:name)
      @equivalencies = @equivalencies.page(params[:page]).per(25)
    end

    def sync
      authorize Transfer::Equivalency

      TransferEquivalencySyncJob.perform_later
      redirect_to admin_transfer_equivalencies_path, notice: "Transfer equivalency sync queued successfully."
    end

  end
end
