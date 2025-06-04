class EnsureFundraiserDatesAreNullable < ActiveRecord::Migration[7.2]
  def change
    # This migration serves as documentation that start_date and end_date
    # in the fundraisers table are intentionally nullable to support
    # indefinite fundraisers that have no end date.
    # 
    # The columns are already nullable in the schema, so no actual changes
    # are needed.
    #
    # The change method is empty because we're just documenting the intent,
    # not actually changing the schema.
  end
end
