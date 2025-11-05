# frozen_string_literal: true

module Admin
  class UsersController < Admin::ApplicationController
    before_action :set_user, only: [:show, :edit, :update, :destroy, :revoke_oauth_credential, :enable_beta, :disable_beta]

    BETA_FEATURE_FLAG = :"2025_10_04_beta_test"

    def index
      @users = User.order(created_at: :desc)

      if params[:search].present?
        @users = @users.where("email ILIKE ?", "%#{params[:search]}%")
      end

      # For Turbo Frame requests, only render the frame
      return unless turbo_frame_request?

      render partial: "users_table"

    end

    def show
    end

    def edit
    end

    def update
      if @user.update(user_params)
        redirect_to admin_user_path(@user), notice: "User was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @user.destroy
      redirect_to admin_users_path, notice: "User was successfully deleted."
    end

    def revoke_oauth_credential
      credential = @user.oauth_credentials.find(params[:credential_id])
      credential_email = credential.email

      # Queue the revocation job
      RevokeOauthCredentialJob.perform_later(credential.id)

      redirect_to admin_user_path(@user), notice: "OAuth credential for #{credential_email} is being revoked."
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_user_path(@user), alert: "OAuth credential not found."
    end

    def enable_beta
      Flipper.enable_actor(BETA_FEATURE_FLAG, @user)
      redirect_to admin_user_path(@user), notice: "#{@user.email} has been added to the beta test group."
    rescue => e
      Rails.logger.error("Error adding user to beta: #{e.message}")
      redirect_to admin_user_path(@user), alert: "Failed to add user to beta: #{e.message}"
    end

    def disable_beta
      Flipper.disable_actor(BETA_FEATURE_FLAG, @user)
      redirect_to admin_user_path(@user), notice: "Beta tester access removed for #{@user.email}."
    rescue => e
      Rails.logger.error("Error removing user from beta: #{e.message}")
      redirect_to admin_user_path(@user), alert: "Failed to remove user from beta: #{e.message}"
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    def user_params
      params.expect(user: [:email, :first_name, :last_name, :access_level])
    end

  end
end
