# frozen_string_literal: true

require "rails_helper"

RSpec.describe BackfillEmbeddingsJob, :embeddings do
  include ActiveJob::TestHelper

  let(:term) { create(:term) }

  it "queues a batch job for the records that need a vector" do
    course = create(:course, term: term)

    expect { described_class.perform_now("Course") }
      .to have_enqueued_job(GenerateEmbeddingsJob).with("Course", [ course.id ])
  end

  it "queues nothing when every record is current" do
    give_embedding(create(:course, term: term), 0.25)

    expect { described_class.perform_now("Course") }.not_to have_enqueued_job(GenerateEmbeddingsJob)
  end

  it "leaves out cancelled sections" do
    create(:course, term: term, status: "cancelled")

    expect { described_class.perform_now("Course") }.not_to have_enqueued_job(GenerateEmbeddingsJob)
  end

  it "leaves out reviews with no comment" do
    faculty = create(:faculty)
    create(:rmp_rating, faculty: faculty, comment: nil)

    expect { described_class.perform_now("RmpRating") }.not_to have_enqueued_job(GenerateEmbeddingsJob)
  end

  it "covers every model when it is given none" do
    create(:course, term: term)

    expect { described_class.perform_now }.to have_enqueued_job(GenerateEmbeddingsJob).with("Course", anything)
  end

  it "queues nothing without an API key" do
    create(:course, term: term)
    ENV.delete("OPENAI_API_KEY")

    expect { described_class.perform_now }.not_to have_enqueued_job(GenerateEmbeddingsJob)
  end

  it "raises for a model it does not own" do
    expect { described_class.perform_now("User") }.to raise_error(ArgumentError, /Unknown model/)
  end
end
