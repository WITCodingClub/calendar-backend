# frozen_string_literal: true

class Dashboard::ConnectedAccountsController < Dashboard::ApplicationController
  def index
    authorize current_user, :show?

    credentials = current_user.oauth_credentials.includes(:course_calendar).order(:created_at).to_a
    @credentials = credentials.select { |credential| credential.provider == "google" }
    @can_disconnect = credentials.size > 1
    @add_account_url = add_account_url

    # The Outlook section shows only while the Microsoft Graph provider is on
    # for this person, like the extension endpoints.
    @microsoft_enabled = MicrosoftGraph.enabled_for?(current_user)
    return unless @microsoft_enabled

    @microsoft_credentials = credentials.select { |credential| credential.provider == "microsoft" }
    @microsoft_connect_url = microsoft_connect_url
  end

  def destroy
    credential = current_user.oauth_credentials.find_by(id: params[:id])

    unless credential
      # Try encoded ID lookup
      credential = OauthCredential.find_by_public_id(params[:id])
      credential = nil unless credential&.user_id == current_user.id
    end

    unless credential
      skip_authorization
      return redirect_to dashboard_connected_accounts_path, alert: "Credential not found."
    end

    authorize credential, :destroy?

    if current_user.oauth_credentials.one?
      redirect_to dashboard_connected_accounts_path,
                  alert: "Cannot disconnect your only connected account."
      return
    end

    credential.destroy!
    redirect_to dashboard_connected_accounts_path, notice: "Account disconnected."
  end

  private

  def add_account_url
    state = GoogleOauthStateService.generate_state(
      user_id: current_user.id,
      email:   current_user.email
    )
    "/auth/google_oauth2?state=#{CGI.escape(state)}"
  end

  def microsoft_connect_url
    state = MicrosoftGraph::OauthState.generate(user_id: current_user.id)
    microsoft_graph_auth_path(state: state)
  end
end
