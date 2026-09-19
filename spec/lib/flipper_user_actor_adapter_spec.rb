# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlipperUserActorAdapter do
  let(:user) { create(:user) }
  let(:feature) { Flipper[:env_switcher] }

  # The Flipper UI wraps each typed value in Flipper::Actor, as these examples do.
  def typed(value) = Flipper::Actor.new(value)

  describe "enable" do
    it "saves an email as the user's flipper_id" do
      feature.enable_actor(typed(user.email))

      expect(feature.actors_value).to eq(Set[user.flipper_id])
      expect(Flipper.enabled?(:env_switcher, user)).to be(true)
    end

    it "saves a public id as the user's flipper_id" do
      feature.enable_actor(typed(user.public_id))

      expect(feature.actors_value).to eq(Set[user.flipper_id])
    end

    it "saves a flipper_id unchanged" do
      feature.enable_actor(typed(user.flipper_id))

      expect(feature.actors_value).to eq(Set[user.flipper_id])
    end

    it "saves a value that matches no user as typed" do
      feature.enable_actor(typed("nobody@example.com"))

      expect(feature.actors_value).to eq(Set["nobody@example.com"])
    end
  end

  describe "disable" do
    it "removes the user's gate when the admin types an email" do
      feature.enable_actor(user)
      feature.disable_actor(typed(user.email))

      expect(feature.actors_value).to be_empty
    end

    it "removes a gate that was saved as an email before the adapter" do
      Flipper::Adapters::ActiveRecord.new.enable(feature, feature.gate(:actor), Flipper::Types::Actor.new(typed(user.email)))
      feature.disable_actor(typed(user.email))

      expect(feature.actors_value).to be_empty
    end
  end

  it "passes other gates through unchanged" do
    feature.enable_group(:admins)

    expect(feature.groups_value).to eq(Set["admins"])
  end
end
