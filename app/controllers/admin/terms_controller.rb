# frozen_string_literal: true

module Admin
  class TermsController < Admin::ApplicationController
    def index
      @terms = Term.order(year: :desc, season: :desc).page(params[:page]).per(10)
    end

    def show
      @term = Term.find_by_public_id!(params[:id]) # rubocop:disable Rails/DynamicFindBy
      @courses = @term.courses
                      .includes(:faculties, meeting_times: [rooms: :building])
                      .order(:title)
                      .page(params[:page]).per(20)
    end
  end
end
