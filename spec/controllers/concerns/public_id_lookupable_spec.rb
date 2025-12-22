# frozen_string_literal: true

require "rails_helper"

RSpec.describe PublicIdLookupable do
  # Create a test controller that includes the concern
  let(:controller) do
    Class.new do
      include PublicIdLookupable
    end.new
  end

  describe "#find_by_any_id" do
    let!(:user) { create(:user) }

    context "with a public_id" do
      it "finds the record by public_id" do
        result = controller.find_by_any_id(User, user.public_id)
        expect(result).to eq(user)
      end

      it "returns nil for invalid public_id" do
        result = controller.find_by_any_id(User, "usr_invalid123")
        expect(result).to be_nil
      end

      it "returns nil for wrong model prefix" do
        result = controller.find_by_any_id(User, "oac_#{user.hashid}")
        expect(result).to be_nil
      end
    end

    context "with an internal ID" do
      it "finds the record by internal ID" do
        result = controller.find_by_any_id(User, user.id)
        expect(result).to eq(user)
      end

      it "finds the record by internal ID as string" do
        result = controller.find_by_any_id(User, user.id.to_s)
        expect(result).to eq(user)
      end

      it "returns nil for non-existent internal ID" do
        result = controller.find_by_any_id(User, 99999)
        expect(result).to be_nil
      end
    end

    context "with blank input" do
      it "returns nil for nil" do
        result = controller.find_by_any_id(User, nil)
        expect(result).to be_nil
      end

      it "returns nil for empty string" do
        result = controller.find_by_any_id(User, "")
        expect(result).to be_nil
      end
    end
  end

  describe "#find_by_any_id!" do
    let!(:user) { create(:user) }

    context "with a valid ID" do
      it "finds the record by public_id" do
        result = controller.find_by_any_id!(User, user.public_id)
        expect(result).to eq(user)
      end

      it "finds the record by internal ID" do
        result = controller.find_by_any_id!(User, user.id)
        expect(result).to eq(user)
      end
    end

    context "with an invalid ID" do
      it "raises RecordNotFound for invalid public_id" do
        expect {
          controller.find_by_any_id!(User, "usr_invalid123")
        }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it "raises RecordNotFound for non-existent internal ID" do
        expect {
          controller.find_by_any_id!(User, 99999)
        }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it "raises RecordNotFound for blank input" do
        expect {
          controller.find_by_any_id!(User, nil)
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
