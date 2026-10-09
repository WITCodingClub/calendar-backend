# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Devise account pages", type: :request do
  let(:user) { create(:user) }

  def expect_styled_page(heading)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<html lang="en"', '<meta charset="utf-8">')
    expect(response.body).to include("m3-card", "m3-input", "m3-btn-filled")
    expect(response.body).to include(heading)
    expect(response.body).to include(new_user_session_path)
  end

  it "styles the forgot password page" do
    get new_user_password_path

    expect_styled_page("Reset your password")
    expect(response.body).to include("<title>Reset Password — WIT Calendar</title>")
  end

  it "styles the new password page that the reset email links to" do
    token = user.send_reset_password_instructions

    get edit_user_password_path(reset_password_token: token)

    expect_styled_page("Set a new password")
    expect(response.body).to include("At least #{Devise.password_length.min} characters.")
  end

  it "styles the resend confirmation page" do
    get new_user_confirmation_path

    expect_styled_page("Confirm your account")
  end

  it "styles the resend unlock page" do
    get new_user_unlock_path

    expect_styled_page("Unlock your account")
  end

  it "shows form errors in an alert that screen readers announce" do
    post user_confirmation_path, params: { user: { email: "nobody@wit.edu" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('class="m3-alert-error', 'role="alert"', "Email not found")
  end

  it "shows a bad confirmation link as an error on the styled page" do
    get user_confirmation_path(confirmation_token: "not-a-token")

    expect(response.body).to include("m3-card", 'role="alert"', "Confirmation token is invalid")
  end

  it "has no unused Devise sign-in view, because users/sessions/new is the sign-in page" do
    expect(Rails.root.join("app/views/devise/sessions/new.html.erb")).not_to exist

    get new_user_session_path

    expect(response.body).to include("Sign in with Google")
  end
end
