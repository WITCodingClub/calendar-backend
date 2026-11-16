# frozen_string_literal: true

module Api
  class BusyBlocksController < BaseController
    include Api::BusyBlocksParams

    authenticate_with_token

    # The busy blocks of the signed-in user, built by the same service as
    # GET /api/friends/:friend_id/busy_blocks. The client can then compare both
    # sides with the same logic. It sends the data of the user only.
    def show
      from, to = busy_blocks_range
      return if performed?

      blocks = BusyBlocks.new(current_user, from: from, to: to).call
      render json: BusyBlocksSerializer.new(blocks, from: from, to: to).as_json, status: :ok
    end
  end
end
