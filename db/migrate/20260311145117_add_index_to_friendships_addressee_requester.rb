# frozen_string_literal: true

class AddIndexToFriendshipsAddresseeRequester < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :friendships, [:addressee_id, :requester_id],
              name: "index_friendships_on_addressee_id_and_requester_id",
              algorithm: :concurrently
  end

end
