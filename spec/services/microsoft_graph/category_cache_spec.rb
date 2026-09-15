# frozen_string_literal: true

require "rails_helper"

RSpec.describe MicrosoftGraph::CategoryCache, :microsoft_graph do
  subject(:cache) { described_class.new(MicrosoftGraph::Client.new(credential)) }

  let(:credential) { create(:oauth_credential, :microsoft, token_expires_at: 1.hour.from_now) }
  let(:categories_url) { "#{MicrosoftGraphHelpers::GRAPH_URL}/me/outlook/masterCategories" }

  def stub_master_list(fixture = "master_categories", status: 200)
    stub_request(:get, categories_url).with(query: hash_including({})).to_return(graph_json_response(fixture, status: status))
  end

  it "gives no category to an event without a color" do
    expect(cache.name_for(nil)).to be_nil
    expect(a_request(:any, /graph\.microsoft\.com/)).not_to have_been_made
  end

  it "reuses a category the person already has" do
    list = stub_master_list

    expect(cache.name_for(11)).to eq("WIT Tomato")
    expect(list).to have_been_requested.once
    expect(a_request(:post, categories_url)).not_to have_been_made
  end

  it "creates a missing category with the closest preset color, once for each sync" do
    list   = stub_master_list
    create = stub_request(:post, categories_url)
             .with(body: { displayName: "WIT Graphite", color: "preset12" }.to_json)
             .to_return(graph_json_response("master_category_created", status: 201))

    expect(cache.name_for("8")).to eq("WIT Graphite")
    expect(cache.name_for(8)).to eq("WIT Graphite")
    expect(cache.name_for(11)).to eq("WIT Tomato")

    expect(list).to have_been_requested.once
    expect(create).to have_been_requested.once
  end

  it "still names the category when the mailbox settings scope is missing" do
    list = stub_master_list("error_forbidden", status: 403)

    expect(cache.name_for(8)).to eq("WIT Graphite")
    expect(cache.name_for(9)).to eq("WIT Blueberry")
    expect(list).to have_been_requested.once
    expect(a_request(:post, categories_url)).not_to have_been_made
  end

  it "maps every Google color to a distinct Outlook preset" do
    presets = described_class::COLORS.values.map(&:last)

    expect(described_class::COLORS.keys).to eq((1..11).to_a)
    expect(presets.uniq.size).to eq(11)
    expect(presets).to all(match(/\Apreset([0-9]|1[0-9]|2[0-4])\z/))
  end
end
