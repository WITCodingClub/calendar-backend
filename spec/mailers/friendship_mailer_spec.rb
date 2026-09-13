# frozen_string_literal: true

require "rails_helper"

RSpec.describe FriendshipMailer, type: :mailer do
  let(:requester) do
    User.create!(email: "requester@wit.edu", password: "password123",
                 first_name: "Ada", last_name: "Lovelace")
  end
  let(:addressee) do
    User.create!(email: "addressee@wit.edu", password: "password123",
                 first_name: "Grace", last_name: "Hopper")
  end
  let(:friendship) { Friendship.new(requester: requester, addressee: addressee) }

  describe "#request_received" do
    subject(:mail) { described_class.request_received(friendship) }

    it "addresses the requestee" do
      expect(mail.to).to eq([ "addressee@wit.edu" ])
    end

    it "names the requester in the subject" do
      expect(mail.subject).to eq("Ada Lovelace sent you a friend request on WIT Calendar")
    end

    it "names the requester and links to the requests page in both parts" do
      html = mail.html_part.body.to_s
      text = mail.text_part.body.to_s

      expect(html).to include("Ada Lovelace").and include("Hi Grace")
      expect(html).to include("http://example.com/dashboard/friends/requests")
      expect(text).to include("Ada Lovelace").and include("Hi Grace")
      expect(text).to include("http://example.com/dashboard/friends/requests")
    end

    it "falls back to the email address when the requester has no name" do
      requester.update!(first_name: nil, last_name: nil)

      expect(mail.subject).to eq("requester@wit.edu sent you a friend request on WIT Calendar")
    end

    it "omits the first name when the requestee has none" do
      addressee.update!(first_name: nil, last_name: nil)

      expect(mail.text_part.body.to_s).to include("Hi,")
    end
  end
end
