# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Flash messages", type: :request do
  def flash_stack
    Nokogiri::HTML(response.body).at_css("#flash-messages")
  end

  context "when the sign-in page has an alert" do
    before do
      # Devise sends a visit with no reset token back to sign-in with an alert.
      get edit_user_password_path
      follow_redirect!
    end

    it "announces the alert and keeps it until the user closes it" do
      message = flash_stack.at_css('[role="alert"]')

      expect(message.text).to include("without coming from a password reset email")
      expect(message["data-flash-message-timeout-value"]).to eq("0")
      expect(message.at_css('button[aria-label="Dismiss"]')).to be_present
    end

    it "shows the message one time only" do
      expect(response.body.scan("without coming from a password reset email").size).to eq(1)
    end

    it "places the stack at the top, because the page has no top bar" do
      expect(flash_stack["class"].split).to include("top-4")
      expect(flash_stack["class"].split).not_to include("top-16")
    end
  end

  context "when a Devise page redirects to sign-in with a notice" do
    let(:user) { create(:user) }

    it "announces the notice as a status, one time only" do
      post user_password_path, params: { user: { email: user.email } }
      follow_redirect!

      message = flash_stack.at_css('[role="status"]')
      expect(message).to be_present
      expect(response.body.scan(message.at_css("p").text).size).to eq(1)
    end
  end

  context "when a user is on the dashboard" do
    let(:user) { create(:user, :with_processed_courses) }

    before { sign_in user }

    it "places the stack below the mobile top bar" do
      get dashboard_root_path

      expect(flash_stack["class"].split).to include("top-16", "lg:top-4")
    end
  end
end
