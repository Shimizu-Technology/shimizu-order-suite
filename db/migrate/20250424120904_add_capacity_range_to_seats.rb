class AddCapacityRangeToSeats < ActiveRecord::Migration[7.2]
  def change
    # Set min_capacity default to 1 (same as current capacity default)
    add_column :seats, :min_capacity, :integer, default: 1, null: false
    
    # For max_capacity, we'll set it to NULL initially, which will mean
    # the seat has no upper limit (using the current capacity as both min and max)
    add_column :seats, :max_capacity, :integer
    
    # Update existing records to have max_capacity equal to capacity
    # This ensures existing seats have reasonable values
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE seats 
          SET max_capacity = capacity 
          WHERE max_capacity IS NULL;
        SQL
      end
    end
    
    # Add a check constraint to ensure min_capacity <= max_capacity when max_capacity is not null
    add_check_constraint :seats, "(max_capacity IS NULL) OR (min_capacity <= max_capacity)", name: "check_min_max_capacity"
  end
end
