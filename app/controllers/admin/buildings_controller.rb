# frozen_string_literal: true

module Admin
  class BuildingsController < Admin::ApplicationController
    def index
      @buildings = Building.order(:name).page(params[:page]).per(7)
    end

  end
end
