class MakeEndDateOptionalInWholesaleFundraisers < ActiveRecord::Migration[7.2]
  def change
    change_column_null :wholesale_fundraisers, :end_date, true
  end
end
