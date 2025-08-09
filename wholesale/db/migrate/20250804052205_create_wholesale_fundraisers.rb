class CreateWholesaleFundraisers < ActiveRecord::Migration[8.0]
  def change
    create_table :wholesale_fundraisers do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.string :contact_email
      t.string :contact_phone
      t.text :terms_and_conditions
      t.boolean :active, default: true
      t.jsonb :settings, default: {}
      
      t.timestamps
    end
    
    # Indexes for performance and uniqueness
    add_index :wholesale_fundraisers, [:restaurant_id, :slug], unique: true
    add_index :wholesale_fundraisers, [:restaurant_id, :active]
    add_index :wholesale_fundraisers, [:start_date, :end_date]
  end
end
