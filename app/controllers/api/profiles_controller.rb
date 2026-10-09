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

    # GET /api/user/email (legacy, see config/routes/api/legacy.rb)
    def email
      authorize current_user, :show?
      render json: { email: current_user.email }, status: :ok
    end

    # GET /api/user/ics_url (legacy, see config/routes/api/legacy.rb)
    def ics_url
      authorize current_user, :show?
      render json: { ics_url: current_user.cal_url_with_extension }, status: :ok
    end
  end
end
