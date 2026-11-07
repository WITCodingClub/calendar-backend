# frozen_string_literal: true

module Dashboard
  class IcsFeedsController < Dashboard::ApplicationController
    def show
      authorize current_user, :show?
      @ics_url = current_user.cal_url_with_extension
      # Calendar apps open a webcal:// link as a subscription to the same feed.
      @webcal_url = @ics_url.sub(%r{\Ahttps?://}, "webcal://")
    end
  end
end
