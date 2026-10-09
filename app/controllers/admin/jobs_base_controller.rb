# frozen_string_literal: true

module Admin
  # The base class of the Mission Control job dashboard (see
  # config/application.rb). The dashboard actions are gem code and never call
  # authorize, so verify_authorized would turn every page into a 500.
  # SuperAdminConstraint in config/routes/admin.rb guards the whole engine.
  class JobsBaseController < Admin::ApplicationController
    skip_after_action :verify_authorized
  end
end
