# frozen_string_literal: true

require "rails_helper"

RSpec.describe CatalogCoursePolicy do
  let(:record) { build(:catalog_course) }

  %i[index? show?].each do |query|
    describe "##{query}" do
      it "permits a signed-in user" do
        expect(described_class.new(build(:user), record).public_send(query)).to be(true)
      end

      it "refuses a guest" do
        expect(described_class.new(nil, record).public_send(query)).to be(false)
      end
    end
  end

  %i[create? update?].each do |query|
    describe "##{query}" do
      it "permits an admin" do
        expect(described_class.new(build(:user, access_level: :admin), record).public_send(query)).to be(true)
      end

      it "refuses a user without admin access" do
        expect(described_class.new(build(:user), record).public_send(query)).to be_falsey
      end
    end
  end

  describe "#destroy?" do
    it "refuses an admin who is not a super admin" do
      expect(described_class.new(build(:user, access_level: :admin), record).destroy?).to be_falsey
    end
  end

  describe CatalogCoursePolicy::Scope do
    it "resolves every course" do
      course = create(:catalog_course)

      expect(described_class.new(build(:user), CatalogCourse.all).resolve).to contain_exactly(course)
    end
  end
end
