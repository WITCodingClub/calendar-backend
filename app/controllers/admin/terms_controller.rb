# frozen_string_literal: true

module Admin
  class TermsController < Admin::ApplicationController
    def index
      @terms = Term.order(year: :desc, season: :desc).page(params[:page]).per(10)
    end

  end
end
