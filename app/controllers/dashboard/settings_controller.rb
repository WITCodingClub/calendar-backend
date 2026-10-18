# frozen_string_literal: true

module Dashboard
  class SettingsController < Dashboard::ApplicationController
    # An account page. It works before the user processes any courses.
    skip_before_action :require_processed_courses

    def show
      authorize current_user, :show?

      @sign_in_identities = current_user.sign_in_identities.order(:created_at)
      @connected_apps     = Doorkeeper::Application.authorized_for(current_user).order(:name)
      @connected_app_scopes = connected_app_scopes
    end

    private

    # The scopes each connected app holds, from every token the student has
    # not revoked (McpTools::Scopes).
    def connected_app_scopes
      Doorkeeper::AccessToken.where(resource_owner_id: current_user.id, revoked_at: nil, application_id: @connected_apps.map(&:id))
                             .pluck(:application_id, :scopes)
                             .each_with_object(Hash.new { |hash, id| hash[id] = [] }) do |(id, scopes), result|
                               result[id] |= McpTools::Scopes.expand(scopes)
                             end
    end
  end
end
