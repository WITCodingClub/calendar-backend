# frozen_string_literal: true

require "rails_helper"

RSpec.describe Devise::Mailer, type: :mailer do
  let(:user)    { create(:user) }
  let(:contact) { Rails.application.config.x.contact_email }

  def parts(mail)
    [ mail.html_part.body.decoded, mail.text_part.body.decoded ]
  end

  it "uses ApplicationMailer, so the emails get the shared layout and sender" do
    expect(described_class.superclass).to eq(ApplicationMailer)
    expect(described_class._layout).to eq("mailer")
  end

  it "sends the reset password email with an HTML and a text part" do
    mail = described_class.reset_password_instructions(user, "reset-token")

    expect(mail.subject).to eq("Reset your WIT Calendar password")
    parts(mail).each do |body|
      expect(body).to include("reset_password_token=reset-token", user.email)
    end
    expect(mail.html_part.body.decoded).to include("<html")
  end

  it "sends the confirmation email with an HTML and a text part" do
    mail = described_class.confirmation_instructions(user, "confirm-token")

    expect(mail.subject).to eq("Confirm your email address for WIT Calendar")
    parts(mail).each { |body| expect(body).to include("confirmation_token=confirm-token") }
  end

  it "sends the unlock email with an HTML and a text part" do
    mail = described_class.unlock_instructions(user, "unlock-token")

    expect(mail.subject).to eq("Unlock your WIT Calendar account")
    parts(mail).each { |body| expect(body).to include("unlock_token=unlock-token", contact) }
  end

  it "tells the user who to contact when the password changes" do
    mail = described_class.password_change(user)

    expect(mail.subject).to eq("Your WIT Calendar password changed")
    parts(mail).each { |body| expect(body).to include(user.email, contact) }
  end

  it "names the new address when the email address changes" do
    user.update_columns(unconfirmed_email: "new.address@wit.edu")

    mail = described_class.email_changed(user)

    expect(mail.subject).to eq("Your WIT Calendar email address changed")
    parts(mail).each { |body| expect(body).to include("new.address@wit.edu", contact) }
  end

  # #703: the action is a gold button, and the shared layout adds the logo and
  # the footer.
  {
    reset_password_instructions: [ "Reset my password", "reset_password_token=abc" ],
    confirmation_instructions:   [ "Confirm my email address", "confirmation_token=abc" ],
    unlock_instructions:         [ "Unlock my account", "unlock_token=abc" ]
  }.each do |email, (label, token)|
    it "puts the #{email} link in a button, with the branded layout" do
      mail = described_class.public_send(email, user, "abc")
      html = Nokogiri::HTML(mail.html_part.body.decoded)

      expect(html.at_css("table[role=presentation] td a[href*='#{token}']").text).to eq(label)
      expect(html.at_css("img[src='http://example.com/icon.png']")).to be_present
      expect(mail.text_part.body.decoded).to include("--\nWIT Calendar, from the WIT Coding Club.")
    end
  end
end
