# frozen_string_literal: true

class Dashboard::SettingsController < Dashboard::ApplicationController
  def show
    authorize current_user, :show?
  end
end
