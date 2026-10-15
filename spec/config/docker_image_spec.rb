# frozen_string_literal: true

require "rails_helper"

# The production image installs gems without the development and test groups
# (#688). Specs run with every group, so these examples read the files: code
# that needs a test gem would pass here and fail only in the image.
RSpec.describe "Production Docker image" do
  it "installs no gems from the development or test groups" do
    dockerfile = Rails.root.join("Dockerfile").read
    groups = dockerfile[/BUNDLE_WITHOUT="([^"]*)"/, 1].to_s.split(":")

    expect(groups).to include("development", "test")
  end

  # Constants of gems that only the development and test groups install.
  # Prosopite is left out: its initializer checks defined?(Prosopite) first.
  let(:dev_and_test_constants) { %w[FactoryBot Faker WebMock SimpleCov Shoulda RSpec Brakeman RuboCop] }

  it "has no app or lib code that needs a development or test gem" do
    files = Rails.root.glob("{app,lib}/**/*.{rb,rake}")
    pattern = /\b(#{dev_and_test_constants.join("|")})\b/

    offenders = files.select { |file| file.read.match?(pattern) }.map { |file| file.relative_path_from(Rails.root).to_s }

    expect(offenders).to be_empty
  end
end
