# frozen_string_literal: true

# Helpers for specs that touch embeddings.
#
# Tag an example group with `:embeddings` to give it an OPENAI_API_KEY for the
# example. The key is a placeholder, not a real credential.
#
# Vectors here are deterministic, not real embeddings: `embedding_vector(0.0)`
# points one way and `embedding_vector(1.0)` points another, so a spec can say
# which record should come back first without calling the API.
module EmbeddingHelpers
  API_KEY = "test-openai-key"

  def with_openai_configured
    original = ENV["OPENAI_API_KEY"]
    ENV["OPENAI_API_KEY"] = API_KEY
    yield
  ensure
    original.nil? ? ENV.delete("OPENAI_API_KEY") : ENV["OPENAI_API_KEY"] = original
  end

  # A unit vector in the plane spanned by the first two dimensions. Two
  # vectors built from angles that are close together are close in cosine
  # distance, which is all a nearest-neighbour spec needs.
  def embedding_vector(angle)
    vector    = Array.new(EmbeddingService::DIMENSIONS, 0.0)
    vector[0] = Math.cos(angle * Math::PI / 2)
    vector[1] = Math.sin(angle * Math::PI / 2)
    vector
  end

  # Postgres stores a vector as float4, so a stored vector never compares equal
  # to the float8 array that went in. This matcher allows that rounding.
  def match_vector(vector)
    match(vector.map { |value| a_value_within(1e-6).of(value) })
  end

  # The body OpenAI returns for a batch, one vector per input.
  def openai_embeddings_body(vectors)
    {
      object: "list",
      model:  EmbeddingService::MODEL,
      data:   vectors.each_with_index.map { |vector, index| { object: "embedding", index: index, embedding: vector } },
      usage:  { prompt_tokens: 10 * vectors.length, total_tokens: 10 * vectors.length }
    }.to_json
  end

  def stub_openai_embeddings(vectors)
    stub_request(:post, EmbeddingService::API_URL)
      .to_return(status: 200, body: openai_embeddings_body(vectors), headers: { "Content-Type" => "application/json" })
  end

  # Writes a vector straight onto a record, the way a finished backfill would.
  def give_embedding(record, angle)
    record.store_embedding(embedding_vector(angle))
    record
  end
end

RSpec.configure do |config|
  config.include EmbeddingHelpers

  config.around(:each, :embeddings) do |example|
    with_openai_configured { example.run }
  end

  # Semantic search also needs its flag. The flag is a row, so it is written in
  # a before hook: an around hook runs outside the example's transaction, and
  # the example would not see the row. The after hook clears the Flipper cache,
  # which no transaction rolls back.
  config.around(:each, :semantic_search) do |example|
    with_openai_configured { example.run }
  end

  config.before(:each, :semantic_search) { Flipper.enable(FlipperFlags::SEMANTIC_SEARCH) }
  config.after(:each, :semantic_search)  { Flipper.disable(FlipperFlags::SEMANTIC_SEARCH) }
end
