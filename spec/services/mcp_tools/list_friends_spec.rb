# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::ListFriends do
  let(:user) { create(:user) }

  it "lists accepted friends only" do
    friend = create(:friendship, :accepted, requester: user).addressee
    create(:friendship, requester: user)

    result = described_class.call(server_context: mcp_context(user))

    expect(result.structured_content[:friends]).to eq([ { id: friend.public_id, name: friend.full_name } ])
  end
end
