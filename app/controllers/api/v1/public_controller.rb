# frozen_string_literal: true

module Api
  module V1
    # Base for the public, unauthenticated catalog API.
    #
    # Everything under this controller is read-only course schedule data with no
    # user data of any kind, so no action calls authenticate_with_token, and
    # responses get public cache headers. Errors use the format of
    # Api::ErrorRendering, which docs/public-catalog-api.md documents.
    class PublicController < Api::BaseController
      CACHE_MAX_AGE = 1.hour

      rescue_from ::Catalog::FilterError, with: :render_invalid_filter

      private

      def render_collection(data, meta: {})
        set_public_cache
        render json: { data: data, meta: meta }
      end

      def render_resource(data)
        set_public_cache
        render json: { data: data }
      end

      def set_public_cache
        expires_in CACHE_MAX_AGE, public: true
      end

      def render_invalid_filter(exception)
        render_error exception.message, status: :bad_request, code: "INVALID_FILTER"
      end

      # Page size is capped so one request cannot pull the whole catalog.
      def pagination
        page     = [ params[:page].to_i, 1 ].max
        per_page = params[:per_page].presence&.to_i || ::Catalog::SectionQuery::DEFAULT_PER_PAGE
        per_page = per_page.clamp(1, ::Catalog::SectionQuery::MAX_PER_PAGE)

        [ page, per_page ]
      end

      def boolean_param(key)
        ActiveModel::Type::Boolean.new.cast(params[key]).present?
      end

      def array_param(key)
        value = params[key]
        return nil if value.blank?

        value.is_a?(Array) ? value : value.to_s.split(",").map(&:strip).reject(&:empty?)
      end
    end
  end
end
