class AddImageFieldsToWholesaleFundraisers < ActiveRecord::Migration[7.2]
  def change
    add_column :wholesale_fundraisers, :card_image_url, :string
    add_column :wholesale_fundraisers, :banner_url, :string
  end
end
