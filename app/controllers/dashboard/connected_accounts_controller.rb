# frozen_string_literal: true

class Dashboard::ConnectedAccountsController < Dashboard::ApplicationController
  def index
    authorize current_user, :show?

    @credentials = current_user.oauth_credentials.includes(:google_calendar).order(:created_at)
    @add_account_url = add_account_url
  end

  def destroy
    credential = current_user.oauth_credentials.find_by(id: params[:id])

    unless credential
      # Try encoded ID lookup
      credential = OauthCredential.find_by_public_id(params[:id])
      credential = nil unless credential&.user_id == current_user.id
    end

    return redirect_to dashboard_connected_accounts_path, alert: "Credential not found." unless credential

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
end
