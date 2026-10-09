# frozen_string_literal: true

module Api
  class ProfilesController < BaseController
    authenticate_with_token

    # GET /api/user
    def show
      authorize current_user, :show?
      render json: {
        pub_id:  current_user.public_id,
        email:   current_user.email,
        ics_url: current_user.cal_url_with_extension
      }, status: :ok
    end
  end
end
