# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmailPolicy, type: :policy do
  include_examples "user-owned resource policy", :email
end
