# frozen_string_literal: true

module Api
  class ProfilesController < BaseController
    authenticate_with_token

    # GET /api/user/id
    def pub_id
      authorize current_user, :show?
      render json: { pub_id: current_user.public_id }, status: :ok
    end

    # GET /api/user/email
    def email
      authorize current_user, :show?
      render json: { email: current_user.email }, status: :ok
    end

    # GET /api/user/ics_url
    def ics_url
      authorize current_user, :show?
      render json: { ics_url: current_user.cal_url_with_extension }, status: :ok
    end
  end
end
