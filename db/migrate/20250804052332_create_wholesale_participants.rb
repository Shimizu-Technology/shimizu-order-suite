class CreateWholesaleParticipants < ActiveRecord::Migration[7.2]
  def change
    create_table :wholesale_participants do |t|
      t.references :fundraiser, null: false, foreign_key: { to_table: :wholesale_fundraisers }
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :photo_url
      t.integer :goal_amount_cents
      t.integer :current_amount_cents, default: 0
      t.boolean :active, default: true
      
      t.timestamps
    end
    
    # Indexes for uniqueness and performance
    add_index :wholesale_participants, [:fundraiser_id, :slug], unique: true
    add_index :wholesale_participants, [:fundraiser_id, :active]
  end
end
