# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    if user_signed_in?
      redirect_to after_sign_in_path_for(current_user)
    else
      render plain: "Not Found", status: :not_found
    end
  end
end
