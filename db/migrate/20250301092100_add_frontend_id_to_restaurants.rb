# frozen_string_literal: true

class AddFrontendIdToRestaurants < ActiveRecord::Migration[7.2]
  def change
    add_column :restaurants, :frontend_id, :string, default: 'hafaloha'
  end
end
