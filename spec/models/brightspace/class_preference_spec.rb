# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: brightspace_class_preferences
#
#  id                   :bigint           not null, primary key
#  description_template :text
#  grade_categories     :jsonb
#  grade_mode           :string
#  included_kinds       :string           is an Array
#  location_template    :text
#  reminder_settings    :jsonb
#  sync_enabled         :boolean
#  title_template       :text
#  visibility           :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  color_id             :string
#  course_offering_id   :bigint           not null
#  user_id              :bigint           not null
#
# Indexes
#
#  index_brightspace_class_preferences_on_course_offering_id  (course_offering_id) UNIQUE
#  index_brightspace_class_preferences_on_user_id             (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (course_offering_id => brightspace_course_offerings.id)
#  fk_rails_...  (user_id => users.id)
#
RSpec.describe Brightspace::ClassPreference, type: :model do
  subject { create(:brightspace_class_preference) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:course_offering) }
  it { is_expected.to validate_uniqueness_of(:course_offering_id) }
  it { is_expected.to validate_inclusion_of(:grade_mode).in_array(described_class::GRADE_MODES).allow_nil }
  it { is_expected.to validate_length_of(:title_template).is_at_most(500).allow_blank }
  it { is_expected.to validate_length_of(:description_template).is_at_most(2000).allow_blank }
  it { is_expected.to validate_length_of(:location_template).is_at_most(500).allow_blank }
  it { is_expected.to allow_values("#1a2b3c", nil).for(:color_id) }
  it { is_expected.not_to allow_values("red", "#12345").for(:color_id) }
  it { is_expected.to validate_inclusion_of(:visibility).in_array(%w[public private default]).allow_blank }

  # included_kinds is a Postgres array, which no inclusion matcher covers.
  it "rejects an unknown kind" do
    preference = build(:brightspace_class_preference, included_kinds: %w[quiz survey])

    expect(preference).not_to be_valid
    expect(preference.errors[:included_kinds]).to include("has an unknown kind: survey")
  end

  it "rejects a template with bad syntax" do
    preference = build(:brightspace_class_preference, title_template: "{{title")

    expect(preference).not_to be_valid
    expect(preference.errors[:title_template].first).to start_with("invalid syntax")
  end

  it "validates reminder settings" do
    preference = build(:brightspace_class_preference, reminder_settings: [ { "time" => "x", "type" => "minutes", "method" => "popup" } ])

    expect(preference).not_to be_valid
  end

  # A check across two associations, which no matcher covers.
  it "rejects a class of another user" do
    preference = build(:brightspace_class_preference, user: create(:user))

    expect(preference).not_to be_valid
    expect(preference.errors[:course_offering]).to include("is not one of your classes")
  end

  describe "grade categories" do
    let(:offering) { create(:brightspace_course_offering) }
    let(:category) { create(:brightspace_grade_category, course_offering: offering) }
    let(:item) { create(:brightspace_grade_item, course_offering: offering) }

    it "accepts rules that name rows of the class" do
      preference = build(:brightspace_class_preference, course_offering: offering, grade_categories: [
        { "category_id" => category.public_id, "weight" => 40, "drop_lowest" => 1, "item_ids" => [ item.public_id ] },
        { "name" => "Participation", "weight" => 10, "extra_credit" => false }
      ])

      expect(preference).to be_valid
    end

    it "rejects a category of another class" do
      other = create(:brightspace_grade_category)
      preference = build(:brightspace_class_preference, course_offering: offering,
                                                        grade_categories: [ { "category_id" => other.public_id } ])

      expect(preference).not_to be_valid
      expect(preference.errors[:grade_categories]).to include("item 0 category_id is not a category of this class")
    end

    it "rejects bad values" do
      preference = build(:brightspace_class_preference, course_offering: offering,
                                                        grade_categories: [ { "name" => "Labs", "weight" => -1, "color" => "red" } ])

      expect(preference).not_to be_valid
      expect(preference.errors[:grade_categories]).to include("item 0 has an unknown key: color",
                                                              "item 0 weight must be a number of 0 or more")
    end
  end

  describe "defaults" do
    it "syncs every kind and counts grades as Brightspace does" do
      preference = described_class.new

      expect(preference.effective_sync_enabled).to be(true)
      expect(preference.effective_included_kinds).to eq(Brightspace::Assignment::KINDS)
      expect(preference.effective_grade_mode).to eq("brightspace")
    end
  end
end
