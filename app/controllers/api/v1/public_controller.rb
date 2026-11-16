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

      # Cloudflare caches these responses and ignores Vary: Origin (#684). Rack::Cors
      # adds the CORS header only when the request has an Origin, so a response
      # cached from a server-side request would lack it and break browsers.
      def set_public_cache
        expires_in CACHE_MAX_AGE, public: true
        response.headers["Access-Control-Allow-Origin"] = "*"
      end

      def render_invalid_filter(exception)
        render_error exception.message, status: :bad_request, code: "INVALID_FILTER"
      end

      # A page of a catalog list, with the filters its query object declares
      # (Catalog::Filters), read from the request by their types.
      def list_request(list)
        filters = ::Catalog::ListRequest.query(list).filters.to_h { |filter| [ filter.name, filter_param(filter) ] }.compact
        ::Catalog::ListRequest.new(list, filters, page: params[:page], per_page: params[:per_page])
      end

      def boolean_param(key)
        ::Catalog::Params.boolean(params[key])
      end

      def filter_param(filter)
        case filter.type
        when *::Catalog::Filters::LIST_TYPES then array_param(filter.param)
        when :strict_flag then ::Catalog::Params.strict_boolean(params[filter.param], filter.param)
        else params[filter.param]
        end
      end

      # The term that ?term_uid= names, or nil without one.
      def optional_term
        Term.find_by_uid!(params[:term_uid]) if params[:term_uid].present?
      end

      def similar_limit
        Embeddable.similar_limit(params[:limit])
      end

      def array_param(key)
        value = params[key]
        return nil if value.blank?

        value.is_a?(Array) ? value : value.to_s.split(",").map(&:strip).reject(&:empty?)
      end
    end
  end
end
