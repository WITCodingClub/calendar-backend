# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: rmp_ratings
#
#  id                   :bigint           not null, primary key
#  attendance_mandatory :string
#  clarity_rating       :integer
#  comment              :text
#  course_name          :string
#  difficulty_rating    :integer
#  embedding            :vector(1536)
#  embedding_digest     :string(64)
#  grade                :string
#  helpful_rating       :integer
#  is_for_credit        :boolean
#  is_for_online_class  :boolean
#  rating_date          :datetime
#  rating_tags          :string
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
#  index_rmp_ratings_on_embedding   (embedding) USING hnsw
#  index_rmp_ratings_on_faculty_id  (faculty_id)
#  index_rmp_ratings_on_rmp_id      (rmp_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (faculty_id => faculties.id)
#
RSpec.describe RmpRating, type: :model do
  subject { create(:rmp_rating) }

  it { is_expected.to belong_to(:faculty) }
  it { is_expected.to validate_presence_of(:rmp_id) }
  it { is_expected.to validate_uniqueness_of(:rmp_id) }

  describe "#embedding_text" do
    it "reads the comment with the course it is about" do
      rating = create(:rmp_rating, course_name: "COMP1050", comment: "Lots of group projects.")

      expect(rating.embedding_text).to eq("COMP1050: Lots of group projects.")
    end

    it "is nil for a rating with no comment" do
      expect(create(:rmp_rating, comment: nil).embedding_text).to be_nil
    end
  end
end
