# frozen_string_literal: true

require "rails_helper"

RSpec.describe AdminMailer, type: :mailer do
  describe "#missing_rmp_ids_summary" do
    let(:recipient) { "admin@example.com" }

    context "when faculty are missing RMP IDs" do
      let!(:faculty_without_rmp) { create(:faculty, rmp_id: nil) }
      let(:mail) { described_class.missing_rmp_ids_summary(email: recipient) }

      it "renders a mail object" do
        expect(mail).to be_a(Mail::Message)
      end

      it "sets the recipient correctly" do
        expect(mail.to).to include(recipient)
      end

      it "uses the configured from address" do
        expect(mail.from).to include("noreply@wit.edu")
      end

      it "includes the faculty count in the subject" do
        count = Faculty.where(rmp_id: nil).count
        expect(mail.subject).to include(count.to_s)
      end

      it "mentions 'Missing RMP IDs' in the subject" do
        expect(mail.subject).to match(/Missing RMP IDs/i)
      end

      it "renders both HTML and text parts" do
        expect(mail.body.parts.map(&:content_type)).to include(
          a_string_matching(/text\/html/),
          a_string_matching(/text\/plain/)
        )
      end
    end

    context "when no faculty are missing RMP IDs" do
      before { Faculty.update_all(rmp_id: "some_id") }

      let(:mail) { described_class.missing_rmp_ids_summary(email: recipient) }

      it "returns a null mail message (no delivery)" do
        # AdminMailer returns early when count is zero, resulting in a null message
        expect(mail.body.to_s).to be_empty
      end
    end
  end
end
