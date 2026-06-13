# frozen_string_literal: true

class Dashboard::IcsFeedsController < Dashboard::ApplicationController
  def show
    authorize current_user, :show?
    @ics_url = current_user.cal_url_with_extension
  end
end
