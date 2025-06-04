class CreateFundraisers < ActiveRecord::Migration[7.2]
  def change
    create_table :fundraisers do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :banner_image_url
      t.boolean :active, default: false, null: false
      t.datetime :start_date
      t.datetime :end_date

      t.timestamps
    end
    
    # Add unique index for slug scoped to restaurant_id
    add_index :fundraisers, [:restaurant_id, :slug], unique: true
    
    # Add index for efficient querying of active fundraisers with date ranges
    add_index :fundraisers, [:active, :start_date, :end_date]
  end
end
