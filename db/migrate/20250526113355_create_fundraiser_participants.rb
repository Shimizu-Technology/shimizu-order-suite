class CreateFundraiserParticipants < ActiveRecord::Migration[7.2]
  def change
    create_table :fundraiser_participants do |t|
      t.references :fundraiser, null: false, foreign_key: true
      t.string :name, null: false
      t.string :team
      t.boolean :active, default: true, null: false

      t.timestamps
    end
    
    # Add index for efficient querying of active participants within a fundraiser
    add_index :fundraiser_participants, [:fundraiser_id, :active]
    
    # Add index for team-based queries
    add_index :fundraiser_participants, [:fundraiser_id, :team]
  end
end
