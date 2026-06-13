# app/controllers/robots_controller.rb
class RobotsController < ApplicationController
  def show
    render plain: "User-agent: *\nDisallow: /app/admin\n"
  end
end
