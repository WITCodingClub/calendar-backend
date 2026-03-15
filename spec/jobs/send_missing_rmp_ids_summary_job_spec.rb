# frozen_string_literal: true

require "rails_helper"

RSpec.describe SendMissingRmpIdsSummaryJob do
  describe "queue assignment" do
    it "is assigned to the low queue" do
      expect(described_class.new.queue_name).to eq("low")
    end
  end

  describe "#perform" do
    let(:mail_double) { instance_double(ActionMailer::MessageDelivery, deliver_now: true) }

    before do
      allow(AdminMailer).to receive(:missing_rmp_ids_summary).and_return(mail_double)
    end

    context "when there are faculty without RMP IDs" do
      before { create(:faculty, rmp_id: nil) }

      it "sends the missing RMP IDs summary email" do
        described_class.perform_now

        expect(AdminMailer).to have_received(:missing_rmp_ids_summary)
        expect(mail_double).to have_received(:deliver_now)
      end
    end

    context "when all faculty have RMP IDs" do
      before { Faculty.update_all(rmp_id: "some_id") }

      it "does not send an email" do
        described_class.perform_now

        expect(AdminMailer).not_to have_received(:missing_rmp_ids_summary)
      end
    end

    context "when there are no faculty records at all" do
      before { Faculty.delete_all }

      it "does not send an email" do
        described_class.perform_now

        expect(AdminMailer).not_to have_received(:missing_rmp_ids_summary)
      end
    end
  end
end
