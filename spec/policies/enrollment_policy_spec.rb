# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EnrollmentPolicy, type: :policy do
  include_examples "user-owned resource policy", :enrollment
end
