# frozen_string_literal: true

# The answer that gives the extension a token: onboarding, passkey sign-in, and
# the passkey handoff exchange. The extension reads all three with one code
# path. pub_id is the user's public id without the "usr_" prefix.
class SessionTokenSerializer
  def initialize(user, jwt)
    @user = user
    @jwt  = jwt
  end

  def as_json(*) = { pub_id: @user.hashid, jwt: @jwt }
end
