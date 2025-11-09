# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmailPolicy, type: :policy do
  it_behaves_like "user-owned resource policy", :email
end
