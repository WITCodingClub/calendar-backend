# frozen_string_literal: true

require "rails_helper"

RSpec.describe FriendshipMailer, type: :mailer do
  let(:requester) do
    create(:user, email: "requester@wit.edu", first_name: "Ada", last_name: "Lovelace")
  end
  let(:addressee) do
    create(:user, email: "addressee@wit.edu", first_name: "Grace", last_name: "Hopper")
  end
  let(:friendship) { build(:friendship, requester: requester, addressee: addressee) }

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

    it "leaves out an end date for a permanent request" do
      expect(mail.text_part.body.to_s).not_to include("This friendship ends on")
    end

    context "with an expiry date" do
      let(:friendship) do
        build(:friendship, requester: requester, addressee: addressee,
                           expires_at: Time.zone.local(2099, 12, 1, 23, 59))
      end

      it "gives the end date in both parts" do
        expect(mail.html_part.body.to_s).to include("This friendship ends on December 01, 2099.")
        expect(mail.text_part.body.to_s).to include("This friendship ends on December 01, 2099.")
      end
    end
  end

  describe "#expiry_changed" do
    let(:friendship) do
      create(:friendship, :accepted, requester: requester, addressee: addressee,
                                     expires_at: Time.zone.local(2099, 12, 1, 23, 59))
    end

    def mail_for(event) = described_class.expiry_changed(friendship, requester, event)

    it "goes to the other user" do
      expect(mail_for("shortened").to).to eq([ "addressee@wit.edu" ])
    end

    it "gives the new end date when the actor shortened it" do
      mail = mail_for("shortened")

      expect(mail.subject).to eq("Ada Lovelace changed the end date of your friendship")
      expect(mail.text_part.body.to_s).to include("It now ends on December 01, 2099.")
      expect(mail.html_part.body.to_s).to include("It now ends on December 01, 2099.")
      expect(mail.text_part.body.to_s).to include("http://example.com/dashboard/friends")
    end

    it "says that a proposed date changes nothing until the recipient accepts it" do
      friendship.update!(proposed_by: requester, proposed_expires_at: Time.zone.local(2100, 1, 31, 12))
      mail = mail_for("proposed")

      expect(mail.subject).to eq("Ada Lovelace proposed a new end date for your friendship")
      expect(mail.text_part.body.to_s).to include("proposed a new end date: January 31, 2100. Nothing changes until you accept it.")
    end

    it "names a permanent proposal" do
      friendship.update!(proposed_by: requester, proposed_permanent: true)

      expect(mail_for("proposed").text_part.body.to_s).to include("proposed a permanent friendship.")
    end

    it "reports an accepted proposal" do
      expect(mail_for("proposal_accepted").subject).to eq("Ada Lovelace accepted the new end date for your friendship")
      expect(mail_for("proposal_accepted").text_part.body.to_s).to include("now ends on December 01, 2099.")

      friendship.update!(expires_at: nil)
      expect(mail_for("proposal_accepted").text_part.body.to_s).to include("The friendship is now permanent.")
    end

    it "reports a declined proposal" do
      mail = mail_for("proposal_declined")

      expect(mail.subject).to eq("Ada Lovelace declined the new end date for your friendship")
      expect(mail.text_part.body.to_s).to include("The end date did not change.")
    end

    it "refuses an unknown event" do
      expect { mail_for("deleted").subject }.to raise_error(ArgumentError, /unknown expiry event/)
    end
  end
end
