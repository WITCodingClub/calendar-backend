# frozen_string_literal: true

module Admin
  class FacultiesController < Admin::ApplicationController
    def index
      @faculties = Faculty.order(:last_name, :first_name).page(params[:page])
    end
  end
end
