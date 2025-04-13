class AddPositionToOptions < ActiveRecord::Migration[7.2]
  def change
    add_column :options, :position, :integer, default: 0
    
    # Add an index for efficient ordering
    add_index :options, [:option_group_id, :position]
    
    # Initialize position values for existing records
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE options
          SET position = subquery.row_num
          FROM (
            SELECT id, option_group_id, ROW_NUMBER() OVER (PARTITION BY option_group_id ORDER BY id) as row_num
            FROM options
          ) AS subquery
          WHERE options.id = subquery.id
        SQL
      end
    end
  end
end
