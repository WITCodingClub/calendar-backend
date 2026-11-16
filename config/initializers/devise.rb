# frozen_string_literal: true

Devise.setup do |config|
  config.mailer_sender = Rails.application.config.x.mailer_from

  # ApplicationMailer gives the Devise emails the shared mailer layout.
  config.parent_mailer = "ApplicationMailer"

  require "devise/orm/active_record"

  config.case_insensitive_keys = [ :email ]

  config.strip_whitespace_keys = [ :email ]

  config.skip_session_storage = [ :http_auth ]

  config.stretches = Rails.env.test? ? 1 : 12

  config.reconfirmable = true

  # Google and passkey sign-ins set a remember cookie, so the dashboard stays
  # signed in past the :timeoutable idle limit and after the browser closes.
  config.remember_for = 30.days

  config.expire_all_remember_me_on_sign_out = true

  config.extend_remember_period = true

  config.password_length = 6..128

  config.email_regexp = /\A[^@\s]+@[^@\s]+\z/

  config.reset_password_within = 6.hours

  config.sign_out_via = :delete

  config.router_name = :main_app

  config.responder.error_status = :unprocessable_content
  config.responder.redirect_status = :see_other
end

# The password, confirmation, and unlock pages use the same centered layout as
# the sign-in page. Users::SessionsController sets its own layout.
Rails.application.config.to_prepare do
  [ Devise::PasswordsController, Devise::ConfirmationsController, Devise::UnlocksController ].each do |controller|
    controller.layout "sessions"
  end
end
