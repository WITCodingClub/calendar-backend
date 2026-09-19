# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlipperActorNames do
  let(:user) { create(:user) }

  describe ".call" do
    it "names a user gate by its email" do
      expect(described_class.call([ user.flipper_id ])).to eq(user.flipper_id => user.email)
    end

    it "flags a gate entered as an email and names the flipper_id to use" do
      expect(described_class.call([ user.email ]))
        .to eq(user.email => "NOT MATCHED: enter #{user.flipper_id} for #{user.email}")
    end

    it "flags a gate entered as a public id and names the flipper_id to use" do
      expect(described_class.call([ user.public_id ]))
        .to eq(user.public_id => "NOT MATCHED: enter #{user.flipper_id} for #{user.email}")
    end

    it "flags a gate that matches no user" do
      expect(described_class.call([ "nobody@example.com" ]))
        .to eq("nobody@example.com" => "NOT MATCHED: enter User;<id>")
    end

    it "leaves out a user gate whose user no longer exists" do
      expect(described_class.call([ "User;0" ])).to eq({})
    end
  end

  describe "Flipper UI feature page" do
    it "shows the email next to each actor" do
      Flipper.enable_actor(:env_switcher, user)
      names = Flipper::UI.configuration.actor_names_source.call(Flipper[:env_switcher].actors_value)

      expect(names).to eq(user.flipper_id => user.email)
    end
  end
end
