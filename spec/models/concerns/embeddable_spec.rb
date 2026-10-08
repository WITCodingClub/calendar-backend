# frozen_string_literal: true

require "rails_helper"

# Course stands in for every model that includes the concern. The per-model
# specs cover what each embedding_text says.
RSpec.describe Embeddable do
  let(:term)   { create(:term) }
  let(:course) { create(:course, term: term, title: "Computer Science II") }

  describe "#embedding_stale?" do
    it "is true for a record with no vector" do
      expect(course).to be_embedding_stale
    end

    it "is false right after the vector is stored" do
      give_embedding(course, 0.25)

      expect(course).not_to be_embedding_stale
    end

    it "is true again once the text changes" do
      give_embedding(course, 0.25)
      course.update!(title: "Data Structures")

      expect(course).to be_embedding_stale
    end

    it "is false when the record has no text to embed" do
      rating = create(:rmp_rating, comment: nil)

      expect(rating).not_to be_embedding_stale
    end
  end

  describe "#store_embedding" do
    it "writes the vector and the digest" do
      course.store_embedding(embedding_vector(0.5))

      expect(course.reload.embedding.to_a).to match_vector(embedding_vector(0.5))
      expect(course.embedding_digest).to eq(Course.digest_for(course.embedding_text))
    end

    it "refuses a blank vector" do
      expect(course.store_embedding(nil)).to be(false)
      expect(course.reload.embedding).to be_nil
    end
  end

  describe "scopes" do
    it "splits the rows that have a vector from the rows that do not", :aggregate_failures do
      embedded = give_embedding(create(:course, term: term), 0.25)

      expect(Course.embedded).to contain_exactly(embedded)
      expect(Course.not_embedded).to contain_exactly(course)
    end
  end

  describe ".nearest_to" do
    it "returns the closest rows first" do
      near = give_embedding(create(:course, term: term, title: "near"), 0.10)
      far  = give_embedding(create(:course, term: term, title: "far"), 0.90)

      expect(Course.nearest_to(embedding_vector(0.0))).to eq([ near, far ])
    end

    it "leaves out rows with no vector" do
      give_embedding(course, 0.10)
      create(:course, term: term, title: "no vector")

      expect(Course.nearest_to(embedding_vector(0.0))).to contain_exactly(course)
    end

    it "returns nothing for a blank vector" do
      expect(Course.nearest_to(nil)).to be_empty
    end

    it "stops at the limit" do
      3.times { |index| give_embedding(create(:course, term: term), index * 0.1) }

      expect(Course.nearest_to(embedding_vector(0.0), limit: 2).length).to eq(2)
    end
  end

  describe "#similar" do
    it "returns the closest other rows" do
      give_embedding(course, 0.0)
      near = give_embedding(create(:course, term: term, title: "near"), 0.10)
      give_embedding(create(:course, term: term, title: "far"), 0.95)

      expect(course.similar(limit: 1)).to eq([ near ])
    end

    it "returns nothing when the record has no vector" do
      expect(course.similar).to be_empty
    end
  end
end
