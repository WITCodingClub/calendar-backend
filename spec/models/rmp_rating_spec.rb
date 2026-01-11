# frozen_string_literal: true

# == Schema Information
#
# Table name: rmp_ratings
# Database name: primary
#
#  id                   :bigint           not null, primary key
#  attendance_mandatory :string
#  clarity_rating       :integer
#  comment              :text
#  course_name          :string
#  difficulty_rating    :integer
#  embedding            :vector(1536)
#  grade                :string
#  helpful_rating       :integer
#  is_for_credit        :boolean
#  is_for_online_class  :boolean
#  rating_date          :datetime
#  rating_tags          :text
#  thumbs_down_total    :integer          default(0)
#  thumbs_up_total      :integer          default(0)
#  would_take_again     :boolean
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  faculty_id           :bigint           not null
#  rmp_id               :string           not null
#
# Indexes
#
#  index_rmp_ratings_on_faculty_id  (faculty_id)
#  index_rmp_ratings_on_rmp_id      (rmp_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (faculty_id => faculties.id)
#
require "rails_helper"

RSpec.describe RmpRating do
  describe "validations" do
    it "is valid with valid attributes" do
      rating = build(:rmp_rating)
      expect(rating).to be_valid
    end

    it "requires rmp_id to be present" do
      rating = build(:rmp_rating, rmp_id: nil)
      expect(rating).not_to be_valid
      expect(rating.errors[:rmp_id]).to include("can't be blank")
    end

    it "requires rmp_id to be unique" do
      create(:rmp_rating, rmp_id: "unique123")
      duplicate = build(:rmp_rating, rmp_id: "unique123")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:rmp_id]).to include("has already been taken")
    end
  end

  describe "associations" do
    it "belongs to a faculty" do
      faculty = create(:faculty)
      rating = create(:rmp_rating, faculty: faculty)
      expect(rating.faculty).to eq(faculty)
    end
  end

  describe "scopes" do
    describe ".recent" do
      it "orders by rating_date descending" do
        faculty = create(:faculty)
        old_rating = create(:rmp_rating, faculty: faculty, rating_date: 1.year.ago)
        new_rating = create(:rmp_rating, faculty: faculty, rating_date: 1.day.ago)
        mid_rating = create(:rmp_rating, faculty: faculty, rating_date: 1.month.ago)

        expect(described_class.recent).to eq([new_rating, mid_rating, old_rating])
      end
    end

    describe ".positive" do
      it "returns ratings with clarity_rating >= 4" do
        faculty = create(:faculty)
        positive = create(:rmp_rating, faculty: faculty, clarity_rating: 4)
        very_positive = create(:rmp_rating, faculty: faculty, clarity_rating: 5)
        neutral = create(:rmp_rating, faculty: faculty, clarity_rating: 3)
        negative = create(:rmp_rating, faculty: faculty, clarity_rating: 2)

        result = described_class.positive
        expect(result).to include(positive, very_positive)
        expect(result).not_to include(neutral, negative)
      end
    end

    describe ".negative" do
      it "returns ratings with clarity_rating <= 2" do
        faculty = create(:faculty)
        very_negative = create(:rmp_rating, faculty: faculty, clarity_rating: 1)
        negative = create(:rmp_rating, faculty: faculty, clarity_rating: 2)
        neutral = create(:rmp_rating, faculty: faculty, clarity_rating: 3)
        positive = create(:rmp_rating, faculty: faculty, clarity_rating: 4)

        result = described_class.negative
        expect(result).to include(very_negative, negative)
        expect(result).not_to include(neutral, positive)
      end
    end

    describe ".with_embeddings" do
      it "returns only ratings with embeddings" do
        faculty = create(:faculty)
        with_embedding = create(:rmp_rating, faculty: faculty, embedding: Array.new(1536, 0.1))
        without_embedding = create(:rmp_rating, faculty: faculty, embedding: nil)

        result = described_class.with_embeddings
        expect(result).to include(with_embedding)
        expect(result).not_to include(without_embedding)
      end
    end
  end

  describe "#overall_sentiment" do
    let(:faculty) { create(:faculty) }

    it "returns 'positive' for clarity_rating >= 4" do
      rating = build(:rmp_rating, faculty: faculty, clarity_rating: 4)
      expect(rating.overall_sentiment).to eq("positive")

      rating.clarity_rating = 5
      expect(rating.overall_sentiment).to eq("positive")
    end

    it "returns 'negative' for clarity_rating <= 2" do
      rating = build(:rmp_rating, faculty: faculty, clarity_rating: 2)
      expect(rating.overall_sentiment).to eq("negative")

      rating.clarity_rating = 1
      expect(rating.overall_sentiment).to eq("negative")
    end

    it "returns 'neutral' for clarity_rating of 3" do
      rating = build(:rmp_rating, faculty: faculty, clarity_rating: 3)
      expect(rating.overall_sentiment).to eq("neutral")
    end

    it "returns 'neutral' when clarity_rating is blank" do
      rating = build(:rmp_rating, faculty: faculty, clarity_rating: nil)
      expect(rating.overall_sentiment).to eq("neutral")
    end
  end

  describe "#similar_ratings" do
    it "returns empty relation when embedding is nil" do
      rating = build(:rmp_rating, embedding: nil)
      expect(rating.similar_ratings).to eq(described_class.none)
    end
  end

  describe "#similar_comments_other_faculties" do
    it "returns empty relation when embedding is nil" do
      rating = build(:rmp_rating, embedding: nil)
      expect(rating.similar_comments_other_faculties).to eq(described_class.none)
    end
  end

  describe "public_id" do
    it "generates a public_id with rmp prefix" do
      rating = create(:rmp_rating)
      expect(rating.public_id).to start_with("rmp_")
    end
  end
end
