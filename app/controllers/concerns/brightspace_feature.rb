# frozen_string_literal: true

# Answers 404 while the brightspace flag is off for the current user, so the
# routes look absent until the extension ships the class pages.
module BrightspaceFeature
  extend ActiveSupport::Concern

  included do
    before_action :require_brightspace_flag
  end

  private

  def require_brightspace_flag
    return if Brightspace.enabled_for?(current_user)

    render json: { error: "Not found" }, status: :not_found
  end
end
