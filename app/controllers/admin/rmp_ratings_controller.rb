# frozen_string_literal: true

module Admin
  class RmpRatingsController < Admin::ApplicationController
    PER_PAGE = 7

    def index
      @query    = params[:q].to_s.strip
      @semantic = ActiveModel::Type::Boolean.new.cast(params[:semantic]).present?

      @rmp_ratings = scope.page(params[:page]).per(PER_PAGE)
    end

    private

    def scope
      base = RmpRating.includes(:faculty)
      return base.order(created_at: :desc) if @query.blank?

      ::Catalog::ReviewQuery.new(base).call(q: @query, semantic: @semantic)
    end
  end
end
