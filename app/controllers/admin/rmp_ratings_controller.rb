# frozen_string_literal: true

module Admin
  class RmpRatingsController < Admin::ApplicationController
    def index
      @rmp_ratings = RmpRating.includes(:faculty).order(created_at: :desc).page(params[:page]).per(7)
    end

  end
end
