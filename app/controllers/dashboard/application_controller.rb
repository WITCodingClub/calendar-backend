# frozen_string_literal: true

class Dashboard::ApplicationController < ApplicationController
  layout "user"
  before_action :authenticate_user!
  after_action  :verify_authorized
end
