# frozen_string_literal: true

module Admin
  class BetaTestersController < Admin::ApplicationController
    FEATURE_FLAG = FlipperFlags::V1

    def index
      # Get all actors who have the feature enabled
      flipper_feature = Flipper[FEATURE_FLAG]
      enabled_gate = flipper_feature.gates.find { |gate| gate.name == :actor }

      if enabled_gate
        # Extract user IDs from the enabled actors
        actor_ids = flipper_feature.actors_value.to_a

        # Fetch users based on their primary emails (since flipper_id returns email)
        @beta_testers = User.joins(:emails)
                            .where(emails: { primary: true })
                            .where(emails: { email: actor_ids })
                            .order(created_at: :desc)
      else
        @beta_testers = []
      end
    end

    def new
      @user = User.new
    end

    def create
      email = params[:email]&.strip

      if email.blank?
        flash[:alert] = "Email is required"
        redirect_to new_admin_beta_tester_path
        return
      end

      # Find or create user by email
      @user = User.find_by(email: email)

      if @user.nil?
        # Create a new user with this email
        @user = User.find_or_create_by_email(email)
      end

      # Enable the beta test feature for this user
      Flipper.enable_actor(FEATURE_FLAG, @user)

      redirect_to admin_beta_testers_path, notice: "#{email} has been added as a beta tester."
    rescue => e
      Rails.logger.error("Error adding beta tester: #{e.message}")
      flash[:alert] = "Failed to add beta tester: #{e.message}"
      redirect_to new_admin_beta_tester_path
    end

    def destroy
      user = User.find(params[:id])

      # Disable the beta test feature for this user
      Flipper.disable_actor(FEATURE_FLAG, user)

      redirect_to admin_beta_testers_path, notice: "Beta tester access removed for #{user.email}."
    rescue => e
      Rails.logger.error("Error removing beta tester: #{e.message}")
      redirect_to admin_beta_testers_path, alert: "Failed to remove beta tester: #{e.message}"
    end

  end
end
