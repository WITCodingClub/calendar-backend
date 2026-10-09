# frozen_string_literal: true

module Dashboard
  # The page that a user sees before the extension processes any of the user's
  # courses (#644). It tells the user to install the extension and process the
  # courses there.
  class OnboardingController < Dashboard::ApplicationController
    skip_before_action :require_processed_courses

    def show
      authorize current_user, :show?

      if onboarding_complete?
        flash.keep
        redirect_to dashboard_root_path
        return
      end

      @extension_install_url = Rails.configuration.x.extension_install_url
      @pending_friend_requests_count = current_user.incoming_friend_requests.pending.count
    end
  end
end
