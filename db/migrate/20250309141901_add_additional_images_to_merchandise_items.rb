class AddAdditionalImagesToMerchandiseItems < ActiveRecord::Migration[7.2]
  def change
    # Use string with default empty array, which will be serialized in the model
    add_column :merchandise_items, :additional_images, :string, default: '[]'
  end
end
