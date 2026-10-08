# frozen_string_literal: true

module Api
  # Receives the data that the extension collected, and reports how fresh the
  # stored data is. See docs/brightspace.md for the payload.
  class BrightspaceSyncsController < ApiController
    include BrightspaceFeature

    # The digest that detects a reused snapshot id reads the raw body, so the
    # body must not get a copy under a wrapper key.
    wrap_parameters false

    rescue_from Brightspace::SyncPayload::Invalid do |error|
      render json: { error: error.message }, status: :unprocessable_content
    end

    rescue_from Brightspace::SyncIngestor::Conflict do |error|
      render json: { error: error.message, code: error.code }, status: :conflict
    end

    # POST /api/brightspace/sync
    def create
      connection = current_user.brightspace_connections.active.first
      authorize connection, :sync? if connection

      result = Brightspace::SyncIngestor.new(user: current_user, params: request.request_parameters).call

      render json: result.body
    end

    # GET /api/brightspace/status
    def status
      connection = Brightspace::Connection.current_for(current_user)
      authorize connection, :show? if connection

      offerings = connection ? connection.course_offerings.order(:title, :id) : []

      render json: {
        connection: Brightspace::ConnectionSerializer.new(connection).as_json,
        classes:    offerings.map { |offering| Brightspace::ClassStatusSerializer.new(offering).as_json }
      }
    end
  end
end
