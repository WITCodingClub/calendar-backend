# frozen_string_literal: true

class ChangeRoomNumberToString < ActiveRecord::Migration[7.1]
  def change
    safety_assured { change_column :rooms, :number, :string }
  end
end
