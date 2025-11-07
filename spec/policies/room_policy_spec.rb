# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RoomPolicy, type: :policy do
  include_examples "public-read resource policy", :room
end
