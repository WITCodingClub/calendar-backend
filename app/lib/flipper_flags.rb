# frozen_string_literal: true

module FlipperFlags
  V1 = :"2025_10_04_v1"
  V2 = :"2025_11_12_v2"

  MAP = {
    v1: V1,
    v2: V2
  }.freeze

  ALL_FLAGS = [
    :v1,
    :v2,
  ].freeze


end
