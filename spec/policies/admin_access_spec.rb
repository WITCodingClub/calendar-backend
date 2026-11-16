# frozen_string_literal: true

require "rails_helper"

# AdminAccess is the one list of admin access levels. These examples check that
# the navigation, the policies, and the route constraints all read it.
RSpec.describe AdminAccess do
  let(:levels) { User.access_levels.keys }
  let(:nav_ids) do
    Admin::NavigationRegistry::CATEGORIES.flat_map { |category| [ category[:id], *category[:items].pluck(:id) ] }
  end

  def user_at(level) = build(:user, access_level: level)

  it "lists only sections that the navigation has" do
    expect(described_class::SECTIONS.keys - nav_ids).to be_empty
  end

  it "lets a user in from the section's level up" do
    expect(levels.map { |level| described_class.allowed?(user_at(level), :console_audits) })
      .to eq([ false, false, false, true ])
    expect(described_class.allowed?(nil, :jobs)).to be(false)
  end

  it "shows a navigation item exactly to the users the item's policy lets in" do
    policies = {
      course_catalog:  ->(user) { CourseCatalogPolicy.new(user, :course_catalog).process? },
      service_account: ->(user) { ServiceAccountPolicy.new(user, :service_account).manage? }
    }

    policies.each do |id, permitted|
      levels.each do |level|
        user = user_at(level)
        expect(Admin::NavigationRegistry.item_for(user, id).present?).to eq(permitted.call(user)), "#{id} for #{level}"
      end
    end
  end

  it "guards each mounted tool with the constraint of its navigation item" do
    helpers = Rails.application.routes.url_helpers
    tools   = Admin::NavigationRegistry::CATEGORIES.flat_map { |category| category[:items] }.select { |item| item[:external] }

    tools.each do |item|
      path  = item[:path].is_a?(Symbol) ? helpers.public_send(item[:path]) : item[:path]
      route = Rails.application.routes.routes.find { |r| r.path.spec.to_s == path }
      sections = route.app.constraints.grep(AdminConstraint).map(&:section)

      expect(sections).to include(item[:id]), "#{path} is not guarded by AdminConstraint.new(:#{item[:id]})"
    end
  end
end
