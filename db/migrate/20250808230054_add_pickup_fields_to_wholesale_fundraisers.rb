class AddPickupFieldsToWholesaleFundraisers < ActiveRecord::Migration[7.2]
  def change
    add_column :wholesale_fundraisers, :pickup_location_name, :string
    add_column :wholesale_fundraisers, :pickup_address, :text
    add_column :wholesale_fundraisers, :pickup_instructions, :text
    add_column :wholesale_fundraisers, :pickup_contact_name, :string
    add_column :wholesale_fundraisers, :pickup_contact_phone, :string
    add_column :wholesale_fundraisers, :pickup_hours, :text
  end
end
