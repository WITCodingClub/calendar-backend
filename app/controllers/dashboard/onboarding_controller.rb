# frozen_string_literal: true

# The page that a user sees before the extension processes any of the user's
# courses (#644). It tells the user to install the extension and process the
# courses there.
class Dashboard::OnboardingController < Dashboard::ApplicationController
  skip_before_action :require_processed_courses

  def show
    authorize current_user, :show?

    if onboarding_complete?
      redirect_to dashboard_root_path
      return
    end

    @extension_install_url = Rails.configuration.x.extension_install_url
  end
end
