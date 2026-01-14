# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmbeddingService do
  let(:api_key) { "test-api-key" }
  let(:service) { described_class.new }
  let(:fake_embedding) { Array.new(1536) { rand(-1.0..1.0) } }

  before do
    allow(Rails.application.credentials).to receive(:dig).with(:openai, :api_key).and_return(api_key)
  end

  describe "#initialize" do
    it "raises ConfigurationError when API key is missing" do
      allow(Rails.application.credentials).to receive(:dig).with(:openai, :api_key).and_return(nil)
      allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return(nil)

      expect { described_class.new }.to raise_error(EmbeddingService::ConfigurationError)
    end

    it "uses ENV variable when credentials are not set" do
      allow(Rails.application.credentials).to receive(:dig).with(:openai, :api_key).and_return(nil)
      allow(ENV).to receive(:fetch).with("OPENAI_API_KEY", nil).and_return("env-api-key")

      expect { described_class.new }.not_to raise_error
    end
  end

  describe "#generate" do
    let(:client) { instance_double(OpenAI::Client) }

    before do
      allow(OpenAI::Client).to receive(:new).and_return(client)
    end

    it "returns nil for blank text" do
      expect(service.generate(nil)).to be_nil
      expect(service.generate("")).to be_nil
      expect(service.generate("   ")).to be_nil
    end

    it "generates embedding for valid text" do
      allow(client).to receive(:embeddings).and_return({
                                                         "data" => [{ "embedding" => fake_embedding }]
                                                       })

      result = service.generate("Test text")

      expect(result).to eq(fake_embedding)
      expect(result.length).to eq(1536)
    end

    it "truncates long text" do
      allow(client).to receive(:embeddings).and_return({
                                                         "data" => [{ "embedding" => fake_embedding }]
                                                       })

      long_text = "a" * 10_000
      service.generate(long_text)

      expect(client).to have_received(:embeddings) do |args|
        expect(args[:parameters][:input].length).to be <= 8003 # 8000 + "..."
      end
    end

    it "raises ApiError on API failure" do
      allow(client).to receive(:embeddings).and_raise(Faraday::Error.new("Connection failed"))

      expect { service.generate("Test") }.to raise_error(EmbeddingService::ApiError)
    end
  end

  describe "#generate_batch" do
    let(:client) { instance_double(OpenAI::Client) }

    before do
      allow(OpenAI::Client).to receive(:new).and_return(client)
    end

    it "returns empty array for empty input" do
      expect(service.generate_batch([])).to eq([])
    end

    it "handles array with some blank texts" do
      allow(client).to receive(:embeddings).and_return({
                                                         "data" => [
                                                           { "index" => 0, "embedding" => fake_embedding },
                                                           { "index" => 1, "embedding" => fake_embedding }
                                                         ]
                                                       })

      result = service.generate_batch(["text1", nil, "text2", ""])

      expect(result[0]).to eq(fake_embedding)
      expect(result[1]).to be_nil
      expect(result[2]).to eq(fake_embedding)
      expect(result[3]).to be_nil
    end
  end

  describe "#embed_record" do
    let(:client) { instance_double(OpenAI::Client) }
    let(:course) { create(:course, title: "Test Course", subject: "Computer Science (COMP)") }

    before do
      allow(OpenAI::Client).to receive(:new).and_return(client)
      allow(client).to receive(:embeddings).and_return({
                                                         "data" => [{ "embedding" => fake_embedding }]
                                                       })
    end

    it "generates and saves embedding for a record" do
      expect(course.embedding).to be_nil

      result = service.embed_record(course)

      expect(result).to be true
      # pgvector stores floats with reduced precision, so we compare lengths
      expect(course.reload.embedding.length).to eq(fake_embedding.length)
      expect(course.reload.embedding).to be_present
    end

    it "returns false for record without embedding_text method" do
      record = instance_double("Record", id: 1) # rubocop:disable RSpec/VerifiedDoubleReference
      allow(record).to receive(:respond_to?).with(:embedding_text).and_return(false)

      expect(service.embed_record(record)).to be false
    end

    it "returns false when embedding_text is blank" do
      allow(course).to receive(:embedding_text).and_return("")

      expect(service.embed_record(course)).to be false
    end
  end
end
