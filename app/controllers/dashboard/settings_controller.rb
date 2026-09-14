# frozen_string_literal: true

class Dashboard::SettingsController < Dashboard::ApplicationController
  def show
    authorize current_user, :show?

    @sign_in_identities = current_user.sign_in_identities.order(:created_at)
  end
end
