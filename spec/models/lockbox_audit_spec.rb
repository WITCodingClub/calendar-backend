# frozen_string_literal: true

require "rails_helper"

RSpec.describe LockboxAudit do
  describe "associations" do
    it "belongs to a polymorphic subject" do
      expect(described_class.reflect_on_association(:subject).macro).to eq(:belongs_to)
      expect(described_class.reflect_on_association(:subject).options[:polymorphic]).to be true
    end

    it "belongs to a polymorphic viewer" do
      expect(described_class.reflect_on_association(:viewer).macro).to eq(:belongs_to)
      expect(described_class.reflect_on_association(:viewer).options[:polymorphic]).to be true
    end
  end

  describe "creation" do
    it "can be created with a user subject and viewer" do
      subject_user = create(:user)
      viewer_user = create(:user)

      audit = create(:lockbox_audit, subject: subject_user, viewer: viewer_user)

      expect(audit).to be_persisted
      expect(audit.subject).to eq(subject_user)
      expect(audit.viewer).to eq(viewer_user)
    end

    it "stores an IP address" do
      audit = create(:lockbox_audit, ip: "192.168.1.1")
      expect(audit.ip).to eq("192.168.1.1")
    end

    it "stores arbitrary data as JSON" do
      data = { "action" => "viewed", "resource" => "token" }
      audit = create(:lockbox_audit, data: data)
      expect(audit.data).to eq(data)
    end
  end
end
