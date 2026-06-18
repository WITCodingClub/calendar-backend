# frozen_string_literal: true

class HomeController < ApplicationController
  def index
      render plain: "Not Found", status: :not_found
  end
end
