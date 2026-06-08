# frozen_string_literal: true

class ErrorsController < ApplicationController
  skip_before_action :authenticate_user!

  def unauthorized
    render status: :forbidden
  end

  def not_found
    render status: :not_found
  end
end
