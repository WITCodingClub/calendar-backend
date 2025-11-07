# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RmpRatingPolicy, type: :policy do
  include_examples "public-read resource policy", :rmp_rating
end
