# frozen_string_literal: true

module Dashboard
  class SignInIdentitiesController < Dashboard::ApplicationController
    # An account page. It works before the user processes any courses.
    skip_before_action :require_processed_courses

    # Unlinks a Microsoft account from sign-in. It ends no session: the current
    # session, and the sessions that Google or a passkey opened, stay signed in.
    def destroy
      identity = current_user.sign_in_identities.find_by(id: params[:id])

      unless identity
        # Scoped to current_user, so there is no record to authorize.
        skip_authorization
        return redirect_to dashboard_settings_path, alert: "Sign-in account not found."
      end

      authorize identity, :destroy?

      identity.destroy!
      redirect_to dashboard_settings_path, notice: "Microsoft sign-in removed."
    end
  end
end
