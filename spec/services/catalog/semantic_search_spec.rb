# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::SemanticSearch do
  let(:term) { create(:term) }

  describe ".available?", :embeddings do
    it "is false until the flag is on" do
      expect(described_class).not_to be_available
    end

    it "is true with the key and the flag", :semantic_search do
      expect(described_class).to be_available
    end

    it "is false without the key", :semantic_search do
      ENV.delete("OPENAI_API_KEY")

      expect(described_class).not_to be_available
    end
  end

  describe ".vector_for", :semantic_search do
    it "embeds the query" do
      stub_openai_embeddings([ embedding_vector(0.4) ])

      expect(described_class.vector_for("intro to programming")).to match_vector(embedding_vector(0.4))
    end

    it "asks the API once for a query it has already embedded" do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      stub_openai_embeddings([ embedding_vector(0.4) ])

      2.times { described_class.vector_for("intro to programming") }

      expect(a_request(:post, EmbeddingService::API_URL)).to have_been_made.once
    end

    it "reads the same cache entry whatever the case of the query" do
      expect(described_class.cache_key("Intro To Programming")).to eq(described_class.cache_key("intro to programming"))
    end

    it "returns nil for a blank query, without calling the API" do
      expect(described_class.vector_for("  ")).to be_nil
      expect(a_request(:post, EmbeddingService::API_URL)).not_to have_been_made
    end

    it "returns nil when the API fails, so the caller can fall back" do
      stub_request(:post, EmbeddingService::API_URL).to_return(status: 500, body: "{}")

      expect(described_class.vector_for("intro to programming")).to be_nil
    end
  end

  describe ".vector_for when search is off", :embeddings do
    it "returns nil without calling the API" do
      expect(described_class.vector_for("intro to programming")).to be_nil
      expect(a_request(:post, EmbeddingService::API_URL)).not_to have_been_made
    end
  end

  describe ".ranked_scope", :semantic_search do
    let!(:near) { give_embedding(create(:course, term: term, title: "near"), 0.05) }
    let!(:far)  { give_embedding(create(:course, term: term, title: "far"), 0.95) }

    before { stub_openai_embeddings([ embedding_vector(0.0) ]) }

    it "returns the closest rows of the scope first" do
      expect(described_class.ranked_scope(Course.all, "anything")).to eq([ near, far ])
    end

    it "ranks only what the scope allows" do
      expect(described_class.ranked_scope(Course.where(id: far.id), "anything")).to eq([ far ])
    end

    it "returns an empty relation when the scope has no embedded rows" do
      expect(described_class.ranked_scope(Course.where(title: "missing"), "anything")).to be_empty
    end

    it "stops at the candidate limit" do
      expect(described_class.ranked_scope(Course.all, "anything", limit: 1)).to eq([ near ])
    end

    it "returns nil when the query cannot be embedded, so the caller falls back" do
      stub_request(:post, EmbeddingService::API_URL).to_return(status: 500, body: "{}")

      expect(described_class.ranked_scope(Course.all, "anything")).to be_nil
    end
  end
end
