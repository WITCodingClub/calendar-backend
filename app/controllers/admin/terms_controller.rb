# frozen_string_literal: true

module Admin
  class TermsController < Admin::ApplicationController
    def index
      @terms = Term.reverse_chronological.page(params[:page]).per(25)
      # One grouped count for the page, not one count for each row.
      @course_counts = Course.where(term_id: @terms.map(&:id)).group(:term_id).count
    end

    def show
      @term = Term.find_by_public_id!(params[:id]) # rubocop:disable Rails/DynamicFindBy
      @courses = @term.courses
                      .includes(:faculties, meeting_times: [ rooms: :building ])
                      .order(:title)
                      .page(params[:page]).per(20)
    end
  end
end
