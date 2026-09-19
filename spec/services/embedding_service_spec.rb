# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmbeddingService, :embeddings do
  subject(:service) { described_class.new }

  describe ".configured?" do
    it "is true when the key is set" do
      expect(described_class).to be_configured
    end

    it "is false without the key", :aggregate_failures do
      ENV.delete("OPENAI_API_KEY")

      expect(described_class).not_to be_configured
      expect(described_class.api_key).to be_nil
    end
  end

  describe "#embed" do
    it "sends the text and returns its vector" do
      vector = embedding_vector(0.25)
      stub   = stub_request(:post, described_class::API_URL)
               .with(
                 headers: { "Authorization" => "Bearer #{EmbeddingHelpers::API_KEY}" },
                 body:    hash_including(
                   "model"      => described_class::MODEL,
                   "dimensions" => described_class::DIMENSIONS,
                   "input"      => [ "COMP1050 Computer Science II" ]
                 )
               )
               .to_return(status: 200, body: openai_embeddings_body([ vector ]),
                          headers: { "Content-Type" => "application/json" })

      expect(service.embed("COMP1050 Computer Science II")).to eq(vector)
      expect(stub).to have_been_requested
    end

    it "returns nil for blank text without calling the API" do
      expect(service.embed("  ")).to be_nil
      expect(a_request(:post, described_class::API_URL)).not_to have_been_made
    end
  end

  describe "#embed_all" do
    it "keeps the order of the input" do
      vectors = [ embedding_vector(0.0), embedding_vector(1.0) ]
      stub_request(:post, described_class::API_URL)
        .to_return(status: 200,
                   body:    { data: vectors.each_with_index.map { |vector, index| { index: 1 - index, embedding: vectors[1 - index] } } }.to_json,
                   headers: { "Content-Type" => "application/json" })

      expect(service.embed_all([ "first", "second" ])).to eq(vectors)
    end

    it "leaves a nil in place of each blank text" do
      stub_openai_embeddings([ embedding_vector(0.5) ])

      expect(service.embed_all([ nil, "real text", "" ])).to eq([ nil, embedding_vector(0.5), nil ])
      expect(a_request(:post, described_class::API_URL)
        .with(body: hash_including("input" => [ "real text" ]))).to have_been_made
    end

    it "sends one request per batch" do
      stub_request(:post, described_class::API_URL).to_return do |request|
        inputs = JSON.parse(request.body).fetch("input")
        { status: 200, body: openai_embeddings_body(inputs.map { embedding_vector(0.5) }),
          headers: { "Content-Type" => "application/json" } }
      end

      texts = Array.new(described_class::MAX_BATCH_SIZE + 1) { |index| "text #{index}" }

      expect(service.embed_all(texts).length).to eq(texts.length)
      expect(a_request(:post, described_class::API_URL)).to have_been_made.twice
    end

    it "makes no request when every text is blank" do
      expect(service.embed_all([ nil, "" ])).to eq([ nil, nil ])
      expect(a_request(:post, described_class::API_URL)).not_to have_been_made
    end

    it "cuts a runaway text to the character limit" do
      stub_openai_embeddings([ embedding_vector(0.5) ])

      service.embed("x" * (described_class::MAX_CHARACTERS + 500))

      expect(a_request(:post, described_class::API_URL)
        .with { |request| JSON.parse(request.body).fetch("input").first.length == described_class::MAX_CHARACTERS })
        .to have_been_made
    end
  end

  describe "failures" do
    it "raises ConfigurationError without a key" do
      ENV.delete("OPENAI_API_KEY")

      expect { service.embed("text") }.to raise_error(described_class::ConfigurationError, /OPENAI_API_KEY/)
    end

    it "raises ApiError with the message OpenAI returned" do
      stub_request(:post, described_class::API_URL)
        .to_return(status: 401, body: { error: { message: "Incorrect API key provided" } }.to_json,
                   headers: { "Content-Type" => "application/json" })

      expect { service.embed("text") }.to raise_error(described_class::ApiError, /401.*Incorrect API key/)
    end

    it "raises ApiError when the batch comes back short" do
      stub_openai_embeddings([ embedding_vector(0.5) ])

      expect { service.embed_all([ "one", "two" ]) }
        .to raise_error(described_class::ApiError, /1 vectors for 2 inputs/)
    end

    it "raises ApiError when the connection fails" do
      stub_request(:post, described_class::API_URL).to_timeout

      expect { service.embed("text") }.to raise_error(described_class::ApiError, /request failed/)
    end
  end
end
