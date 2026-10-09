# frozen_string_literal: true

module Api
  # Base for every API controller, public or signed in. Nothing here requires a
  # token: a controller that needs a signed-in user calls
  # authenticate_with_token (see Api::TokenAuthentication). Every error uses
  # the format in Api::ErrorRendering.
  class BaseController < ActionController::API
    include Pundit::Authorization
    include Api::ErrorRendering
    include Api::LegacyRouteCounting
    include Api::TokenAuthentication
    include Api::PublicIdLookupable
  end
end
