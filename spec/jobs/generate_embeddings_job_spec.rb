# frozen_string_literal: true

require "rails_helper"

RSpec.describe GenerateEmbeddingsJob, :embeddings do
  let(:term)   { create(:term) }
  let(:course) { create(:course, term: term, title: "Computer Science II") }

  it "writes the vector and the digest of the text" do
    stub_openai_embeddings([ embedding_vector(0.25) ])

    described_class.perform_now("Course", [ course.id ])

    expect(course.reload.embedding.to_a).to match_vector(embedding_vector(0.25))
    expect(course.embedding_digest).to eq(Course.digest_for(course.embedding_text))
  end

  it "does not touch updated_at" do
    course.update_columns(updated_at: 3.days.ago) # rubocop:disable Rails/SkipsModelValidations
    was = course.reload.updated_at
    stub_openai_embeddings([ embedding_vector(0.25) ])

    described_class.perform_now("Course", [ course.id ])

    expect(course.reload.updated_at).to eq(was)
  end

  it "skips records whose text has not changed" do
    give_embedding(course, 0.25)

    described_class.perform_now("Course", [ course.id ])

    expect(a_request(:post, EmbeddingService::API_URL)).not_to have_been_made
  end

  it "re-embeds a record whose text changed" do
    give_embedding(course, 0.25)
    course.update!(title: "Data Structures")
    stub_openai_embeddings([ embedding_vector(0.75) ])

    described_class.perform_now("Course", [ course.id ])

    expect(course.reload.embedding.to_a).to match_vector(embedding_vector(0.75))
  end

  it "embeds every stale record in one request" do
    other = create(:course, term: term, title: "Physics I")
    stub_request(:post, EmbeddingService::API_URL).to_return do |request|
      inputs = JSON.parse(request.body).fetch("input")
      { status: 200, body: openai_embeddings_body(inputs.map { embedding_vector(0.5) }),
        headers: { "Content-Type" => "application/json" } }
    end

    described_class.perform_now("Course", [ course.id, other.id ])

    expect(a_request(:post, EmbeddingService::API_URL)).to have_been_made.once
    expect([ course.reload.embedding, other.reload.embedding ]).to all(be_present)
  end

  it "ignores a model it does not own" do
    described_class.perform_now("User", [ 1 ])

    expect(a_request(:post, EmbeddingService::API_URL)).not_to have_been_made
  end

  it "does nothing without an API key" do
    ENV.delete("OPENAI_API_KEY")

    expect { described_class.perform_now("Course", [ course.id ]) }.not_to raise_error
    expect(course.reload.embedding).to be_nil
  end
end
