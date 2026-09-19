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

    it "raises for a value that matches no user and saves nothing" do
      expect { feature.enable_actor(typed("nobody@example.com")) }
        .to raise_error(described_class::UnknownActor, /"nobody@example.com" matches no user/)
      expect(feature.actors_value).to be_empty
    end

    it "raises for a flipper_id whose user does not exist" do
      expect { feature.enable_actor(typed("User;0")) }.to raise_error(described_class::UnknownActor)
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

  it "lets the admin remove a gate that matches no user" do
    Flipper::Adapters::ActiveRecord.new.enable(feature, feature.gate(:actor), Flipper::Types::Actor.new(typed("nobody@example.com")))
    feature.disable_actor(typed("nobody@example.com"))

    expect(feature.actors_value).to be_empty
  end

  it "passes other gates through unchanged" do
    feature.enable_group(:admins)

    expect(feature.groups_value).to eq(Set["admins"])
  end

  describe described_class::UnknownActorRedirect do
    it "sends the admin back to the add-actor form with the error" do
      app = ->(_env) { raise FlipperUserActorAdapter::UnknownActor, "\"x\" matches no user." }
      env = Rack::MockRequest.env_for("/admin/flipper/features/env_switcher/actors", method: "POST")

      status, headers, = described_class.new(app).call(env)

      expect(status).to eq(302)
      expect(headers["location"])
        .to eq("/admin/flipper/features/env_switcher/actors?error=%22x%22+matches+no+user.")
    end

    it "passes a normal response through" do
      app = ->(_env) { [ 200, {}, [ "ok" ] ] }

      expect(described_class.new(app).call(Rack::MockRequest.env_for("/"))).to eq([ 200, {}, [ "ok" ] ])
    end
  end
end
