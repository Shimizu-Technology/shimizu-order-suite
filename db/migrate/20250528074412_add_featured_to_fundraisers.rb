class AddFeaturedToFundraisers < ActiveRecord::Migration[7.2]
  def change
    add_column :fundraisers, :featured, :boolean, default: false, null: false
    add_index :fundraisers, :featured
  end
end
