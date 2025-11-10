# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include Authentication
  include Telemetry

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  before_action :set_paper_trail_whodunnit

  # Required by Audits1984 gem for audit logging
  def find_current_auditor
    current_user
  end

end
