# frozen_string_literal: true

require "rails_helper"

# The app has no image_processing gem. With a variant processor set, every
# boot (including each rails runner) prints a warning about the missing gem.
RSpec.describe "Active Storage configuration" do
  it "disables the variant processor" do
    expect(Rails.application.config.active_storage.variant_processor).to eq(:disabled)
  end

  it "does not depend on the image_processing gem" do
    expect(Rails.root.join("Gemfile").read).not_to include("image_processing")
  end
end
