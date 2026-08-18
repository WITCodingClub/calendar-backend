# frozen_string_literal: true

module Api
  module V1
    # Base for the public, unauthenticated catalog API.
    #
    # Deliberately does NOT inherit from Api::ApiController: that base requires
    # a JWT and sits behind a feature flag. Everything under this controller is
    # read-only course schedule data with no user data of any kind.
    class PublicController < ActionController::API
      CACHE_MAX_AGE = 1.hour

      rescue_from ::Catalog::SectionQuery::FilterError, with: :render_bad_request
      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

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

      def render_bad_request(exception)
        render json: { error: exception.message, code: "INVALID_FILTER" }, status: :bad_request
      end

      def render_not_found(exception = nil)
        render json: { error: exception&.message || "Not found", code: "NOT_FOUND" }, status: :not_found
      end

      # Page size is capped so one request cannot pull the whole catalog.
      def pagination
        page     = [ params[:page].to_i, 1 ].max
        per_page = params[:per_page].presence&.to_i || ::Catalog::SectionQuery::DEFAULT_PER_PAGE
        per_page = per_page.clamp(1, ::Catalog::SectionQuery::MAX_PER_PAGE)

        [ page, per_page ]
      end

      def array_param(key)
        value = params[key]
        return nil if value.blank?

        value.is_a?(Array) ? value : value.to_s.split(",").map(&:strip).reject(&:empty?)
      end
    end
  end
end
