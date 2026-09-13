# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationMailer, type: :mailer do
  let(:sender) { Rails.application.config.x.mailer_from }

  it "sends from a domain that Resend can verify" do
    # wit.edu belongs to the university, so it can never hold the DKIM and SPF
    # records Resend needs. Mail from it would be rejected.
    expect(sender).to include("send.witcc.dev")
    expect(sender).not_to include("wit.edu")
  end

  it "uses that sender for every mailer" do
    expect(described_class.default[:from]).to eq(sender)
    expect(AdminMailer.default[:from]).to eq(sender)
    expect(TwentyFiveLiveMailer.default[:from]).to eq(sender)
  end

  it "uses that sender for Devise mail too" do
    expect(Devise.mailer_sender).to eq(sender)
    expect(Devise.mailer_sender).not_to include("please-change-me")
  end
end
