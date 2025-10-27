class ErrorsController < ApplicationController
  def unauthorized
    render :unauthorized, status: :forbidden
  end

  def not_found
    render :not_found, status: :not_found
  end
end
