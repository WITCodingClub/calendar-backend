# frozen_string_literal: true

require "rails_helper"

RSpec.describe UniversityCalendarEventPolicy, type: :policy do
  subject { described_class.new(user, university_calendar_event) }

  let(:university_calendar_event) { create(:university_calendar_event) }

  context "for a guest (nil user)" do
    let(:user) { nil }

    it { is_expected.to permit_action(:index) }
    it { is_expected.to permit_action(:show) }
    it { is_expected.not_to permit_action(:sync) }
    it { is_expected.not_to permit_action(:create) }
    it { is_expected.not_to permit_action(:update) }
    it { is_expected.not_to permit_action(:destroy) }
  end

  context "for a regular user" do
    let(:user) { create(:user, access_level: :user) }

    it { is_expected.to permit_action(:index) }
    it { is_expected.to permit_action(:show) }
    it { is_expected.not_to permit_action(:sync) }
    it { is_expected.not_to permit_action(:create) }
    it { is_expected.not_to permit_action(:update) }
    it { is_expected.not_to permit_action(:destroy) }
  end

  context "for an admin" do
    let(:user) { create(:user, access_level: :admin) }

    it { is_expected.to permit_action(:index) }
    it { is_expected.to permit_action(:show) }
    it { is_expected.to permit_action(:sync) }
    it { is_expected.to permit_action(:create) }
    it { is_expected.to permit_action(:update) }
    it { is_expected.not_to permit_action(:destroy) }
  end

  context "for a super_admin" do
    let(:user) { create(:user, access_level: :super_admin) }

    it { is_expected.to permit_action(:index) }
    it { is_expected.to permit_action(:show) }
    it { is_expected.to permit_action(:sync) }
    it { is_expected.to permit_action(:create) }
    it { is_expected.to permit_action(:update) }
    it { is_expected.to permit_action(:destroy) }
  end

  context "for an owner" do
    let(:user) { create(:user, access_level: :owner) }

    it { is_expected.to permit_action(:index) }
    it { is_expected.to permit_action(:show) }
    it { is_expected.to permit_action(:sync) }
    it { is_expected.to permit_action(:create) }
    it { is_expected.to permit_action(:update) }
    it { is_expected.to permit_action(:destroy) }
  end

  describe "Scope" do
    let(:user) { create(:user) }
    let!(:event1) { create(:university_calendar_event) }
    let!(:event2) { create(:university_calendar_event) }

    it "returns all events for any user" do
      scope = described_class::Scope.new(user, UniversityCalendarEvent).resolve
      expect(scope).to include(event1, event2)
    end

    it "returns all events for nil user" do
      scope = described_class::Scope.new(nil, UniversityCalendarEvent).resolve
      expect(scope).to include(event1, event2)
    end
  end
end
