# frozen_string_literal: true

module Api
  # The one-time catch-up runs the extension does for each student, such as
  # processing past terms after the v6 upgrade
  # (WITCodingClub/calendar-extension#215). The extension reads them on panel
  # load and marks each one done after it finishes.
  class BackfillsController < BaseController
    authenticate_with_token

    # GET /api/user/backfills
    def index
      authorize current_user, :show?

      render json: UserBackfillsSerializer.new(current_user).as_json
    end

    # PUT /api/user/backfills/:name
    def update
      authorize current_user, :update?

      name = params[:name].to_s
      unless UserBackfill::NAMES.value?(name)
        render_error "Unknown backfill: must be one of #{UserBackfill::NAMES.values.join(', ')}", status: :not_found
        return
      end

      UserBackfill.complete!(current_user, name)

      render json: UserBackfillsSerializer.new(current_user).as_json
    end
  end
end
