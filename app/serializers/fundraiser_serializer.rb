# app/serializers/fundraiser_serializer.rb

class FundraiserSerializer < ActiveModel::Serializer
  attributes :id, :restaurant_id, :name, :slug, :description, :banner_image_url, 
             :active, :start_date, :end_date, :created_at, :updated_at
  
  has_many :fundraiser_participants
  has_many :fundraiser_items
  
  def start_date
    object.start_date.iso8601 if object.start_date
  end
  
  def end_date
    object.end_date.iso8601 if object.end_date
  end
  
  def created_at
    object.created_at.iso8601 if object.created_at
  end
  
  def updated_at
    object.updated_at.iso8601 if object.updated_at
  end
end
