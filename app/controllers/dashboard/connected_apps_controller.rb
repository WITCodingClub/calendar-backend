# frozen_string_literal: true

module Dashboard
  # The apps that read the user's data through the MCP server (docs/mcp.md).
  # Settings lists them.
  class ConnectedAppsController < Dashboard::ApplicationController
    # An account page. It works before the user processes any courses.
    skip_before_action :require_processed_courses

    # Revokes every token and grant that the app holds for this user. The app
    # must ask for consent again to read anything.
    def destroy
      app = Doorkeeper::Application.authorized_for(current_user).find_by(id: params[:id])

      unless app
        # Scoped to current_user, so there is no record to authorize.
        skip_authorization
        return redirect_to dashboard_settings_path, alert: "Connected app not found."
      end

      authorize app, :destroy?, policy_class: ConnectedAppPolicy

      Doorkeeper::Application.revoke_tokens_and_grants_for(app.id, current_user)
      redirect_to dashboard_settings_path, notice: "#{app.name} disconnected."
    end
  end
end
