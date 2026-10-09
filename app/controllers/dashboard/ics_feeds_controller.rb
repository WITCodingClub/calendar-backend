# frozen_string_literal: true

module Dashboard
  class IcsFeedsController < Dashboard::ApplicationController
    def show
      authorize current_user, :show?
      @ics_url = current_user.cal_url_with_extension
    end
  end
end
