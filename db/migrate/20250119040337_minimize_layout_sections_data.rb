# db/migrate/20250119000000_minimize_layout_sections_data.rb
class MinimizeLayoutSectionsData < ActiveRecord::Migration[7.2]
  def up
    # 1) Set a default so new Layouts get { "sections": [] } if none is provided
    change_column_default :layouts, :sections_data, from: nil, to: { "sections" => [] }

    # 2) Remove any "seats" arrays from existing layout records
    Layout.find_each do |layout|
      sd = layout.sections_data
      next unless sd.is_a?(Hash) && sd["sections"].is_a?(Array)

      sd["sections"].each do |section|
        # remove the "seats" key entirely (or set it to []).
        section.delete("seats")
      end

      # Save the pruned sections_data back to DB
      layout.update_column(:sections_data, sd)
    end
  end

  def down
    # Revert the default to nil
    change_column_default :layouts, :sections_data, from: { "sections" => [] }, to: nil

    # We can't perfectly restore the seat data we removed, so we do nothing here.
    # If you need to restore, you'd have to have backed it up before removal.
  end
end
