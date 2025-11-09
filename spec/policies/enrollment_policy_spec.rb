# frozen_string_literal: true

require "rails_helper"

RSpec.describe EnrollmentPolicy, type: :policy do
  it_behaves_like "user-owned resource policy", :enrollment
end
