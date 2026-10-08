# frozen_string_literal: true

module Api
  # The Brightspace account that the extension saw for the signed-in user.
  class BrightspaceConnectionsController < ApiController
    include BrightspaceFeature

    # GET /api/user/brightspace_connection
    def show
      connection = current_user.brightspace_connections.active.first
      authorize connection if connection

      render json: { connection: Brightspace::ConnectionSerializer.new(connection).as_json }
    end

    # POST /api/user/brightspace_connection
    def create
      host       = params.require(:host)
      learner_id = params.require(:learner_id)
      authorize Brightspace::Connection.new(user: current_user)

      connection = Brightspace::Connection.link!(user: current_user, host: host.to_s, learner_id: learner_id.to_s)

      render json: { connection: Brightspace::ConnectionSerializer.new(connection).as_json }
    end

    # DELETE /api/user/brightspace_connection
    #
    # Stops imports and calendar sync for the account. The imported data stays,
    # and linking the same account again brings it back.
    def destroy
      connection = current_user.brightspace_connections.active.first
      raise ActiveRecord::RecordNotFound, "No Brightspace account is linked" unless connection

      authorize connection
      connection.disconnect!

      head :no_content
    end
  end
end
