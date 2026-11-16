# frozen_string_literal: true

require "rails_helper"

RSpec.describe PublicIds do
  let(:user) { create(:user) }

  describe ".find" do
    it "finds by public id or by database id" do
      expect(described_class.find(User, user.public_id)).to eq(user)
      expect(described_class.find(User, user.id.to_s)).to eq(user)
    end

    it "finds nothing for a blank id or another model's public id" do
      expect(described_class.find(User, "")).to be_nil
      expect(described_class.find(User, "crs_#{user.public_id.split('_').last}")).to be_nil
      expect { described_class.find!(User, "nope_x") }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe ".decode" do
    it "gives the database id of a public id with the model's prefix, with no query" do
      public_id = user.public_id

      expect(count_queries { expect(described_class.decode(User, public_id)).to eq(user.id) }).to eq(0)
    end

    it "is nil for a bare hashid, a database id, or another prefix" do
      hash = user.public_id.split(described_class.separator).last

      expect(described_class.decode(User, hash)).to be_nil
      expect(described_class.decode(User, user.id.to_s)).to be_nil
      expect(described_class.decode(User, "frm_#{hash}")).to be_nil
    end
  end

  it "adds the model's prefix to a bare hashid" do
    hash = user.public_id.split(described_class.separator).last

    expect(described_class.with_prefix(User, hash)).to eq(user.public_id)
    expect(described_class.with_prefix(User, user.public_id)).to eq(user.public_id)
  end
end
