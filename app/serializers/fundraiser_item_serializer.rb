# app/serializers/fundraiser_item_serializer.rb

class FundraiserItemSerializer < ActiveModel::Serializer
  attributes :id, :fundraiser_id, :name, :description, :price, :image_url, 
             :active, :enable_stock_tracking, :stock_quantity, :low_stock_threshold,
             :available_quantity, :low_stock, :out_of_stock, :created_at, :updated_at
  
  belongs_to :fundraiser
  has_many :option_groups, serializer: OptionGroupSerializer
  
  def price
    object.price.to_f if object.price
  end
  
  def available_quantity
    object.available_quantity
  end
  
  def low_stock
    object.low_stock?
  end
  
  def out_of_stock
    object.out_of_stock?
  end
  
  def created_at
    object.created_at.iso8601 if object.created_at
  end
  
  def updated_at
    object.updated_at.iso8601 if object.updated_at
  end
end
