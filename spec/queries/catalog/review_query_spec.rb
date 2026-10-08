# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::ReviewQuery do
  subject(:query) { described_class.new }

  let(:ada)   { create(:faculty, first_name: "Ada", last_name: "Byron") }
  let(:grace) { create(:faculty, first_name: "Grace", last_name: "Hop") }

  let!(:group_work) do
    create(:rmp_rating, faculty: ada, course_name: "COMP1050", clarity_rating: 5,
                        comment: "Lots of group projects.", rating_date: 2.days.ago)
  end

  let!(:tough_exams) do
    create(:rmp_rating, faculty: ada, course_name: "COMP2000", clarity_rating: 2,
                        comment: "The exams are brutal.", rating_date: 1.day.ago)
  end

  let!(:other_teacher) do
    create(:rmp_rating, faculty: grace, course_name: "MATH1750", clarity_rating: 4,
                        comment: "Clear lectures.", rating_date: 3.days.ago)
  end

  let!(:no_comment) { create(:rmp_rating, faculty: ada, comment: nil) }

  def results(**filters) = query.call(**filters).to_a

  describe "#call with no filters" do
    it "returns the reviews that carry a comment, newest first" do
      expect(results).to eq([ tough_exams, group_work, other_teacher ])
    end

    it "leaves out a review with no comment" do
      expect(results).not_to include(no_comment)
    end
  end

  describe "instructor" do
    it "keeps one instructor's reviews" do
      expect(results(instructor: ada.public_id)).to eq([ tough_exams, group_work ])
    end

    it "rejects an id that belongs to no instructor" do
      expect { results(instructor: "fac_nobody") }
        .to raise_error(described_class::FilterError, /Unknown instructor/)
    end
  end

  describe "sentiment" do
    it "keeps the positive reviews" do
      expect(results(sentiment: "positive")).to eq([ group_work, other_teacher ])
    end

    it "keeps the negative reviews" do
      expect(results(sentiment: "negative")).to eq([ tough_exams ])
    end

    it "rejects a sentiment it does not know" do
      expect { results(sentiment: "grumpy") }.to raise_error(described_class::FilterError, /Unknown sentiment/)
    end
  end

  describe "q" do
    it "matches the comment" do
      expect(results(q: "group projects")).to eq([ group_work ])
    end

    it "matches the course name" do
      expect(results(q: "MATH1750")).to eq([ other_teacher ])
    end

    it "treats LIKE wildcards as literal characters" do
      expect(results(q: "%")).to be_empty
    end
  end

  describe "semantic" do
    context "with search on", :semantic_search do
      before do
        give_embedding(group_work, 0.05)
        give_embedding(tough_exams, 0.50)
        give_embedding(other_teacher, 0.95)
        stub_openai_embeddings([ embedding_vector(0.0) ])
      end

      it "ranks by meaning" do
        expect(results(q: "team assignments", semantic: true)).to eq([ group_work, tough_exams, other_teacher ])
      end

      it "ranks only what the other filters left" do
        expect(results(q: "team assignments", semantic: true, instructor: ada.public_id))
          .to eq([ group_work, tough_exams ])
      end
    end

    context "with search off", :embeddings do
      it "falls back to the literal words" do
        expect(results(q: "group projects", semantic: true)).to eq([ group_work ])
        expect(a_request(:post, EmbeddingService::API_URL)).not_to have_been_made
      end
    end
  end

  it "rejects a filter it does not know" do
    expect { results(nonsense: true) }.to raise_error(described_class::FilterError, /Unknown filter/)
  end
end
