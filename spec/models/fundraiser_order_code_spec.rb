require 'rails_helper'

RSpec.describe Fundraiser, type: :model do
  describe "order_code validations" do
    let(:restaurant) { create(:restaurant) }
    
    it "requires presence of order_code" do
      fundraiser = build(:fundraiser, restaurant: restaurant, order_code: nil)
      expect(fundraiser).not_to be_valid
      expect(fundraiser.errors[:order_code]).to include("can't be blank")
    end
    
    it "ensures uniqueness of order_code scoped to restaurant" do
      create(:fundraiser, restaurant: restaurant, order_code: "F1")
      fundraiser = build(:fundraiser, restaurant: restaurant, order_code: "F1")
      
      expect(fundraiser).not_to be_valid
      expect(fundraiser.errors[:order_code]).to include("has already been taken")
      
      # Should be valid for a different restaurant
      other_restaurant = create(:restaurant)
      fundraiser.restaurant = other_restaurant
      expect(fundraiser).to be_valid
    end
    
    it "validates format of order_code" do
      # Valid formats
      expect(build(:fundraiser, restaurant: restaurant, order_code: "F1")).to be_valid
      expect(build(:fundraiser, restaurant: restaurant, order_code: "TEAM")).to be_valid
      expect(build(:fundraiser, restaurant: restaurant, order_code: "ABC123")).to be_valid
      
      # Invalid formats
      invalid_fundraiser = build(:fundraiser, restaurant: restaurant, order_code: "f1")
      expect(invalid_fundraiser).not_to be_valid
      expect(invalid_fundraiser.errors[:order_code]).to include("must contain only uppercase alphanumeric characters")
      
      invalid_fundraiser = build(:fundraiser, restaurant: restaurant, order_code: "F-1")
      expect(invalid_fundraiser).not_to be_valid
      
      invalid_fundraiser = build(:fundraiser, restaurant: restaurant, order_code: "TOOLONG")
      expect(invalid_fundraiser).not_to be_valid
      expect(invalid_fundraiser.errors[:order_code]).to include("is too long (maximum is 6 characters)")
    end
    
    it "rejects reserved codes" do
      %w[O R RES].each do |reserved_code|
        fundraiser = build(:fundraiser, restaurant: restaurant, order_code: reserved_code)
        expect(fundraiser).not_to be_valid
        expect(fundraiser.errors[:order_code]).to include("is a reserved code and cannot be used")
      end
    end
    
    it "normalizes order_code to uppercase" do
      fundraiser = build(:fundraiser, restaurant: restaurant, order_code: "team")
      fundraiser.valid?
      expect(fundraiser.order_code).to eq("TEAM")
    end
    
    it "strips whitespace from order_code" do
      fundraiser = build(:fundraiser, restaurant: restaurant, order_code: " F1 ")
      fundraiser.valid?
      expect(fundraiser.order_code).to eq("F1")
    end
    
    it "auto-assigns a default order_code if blank" do
      fundraiser = build(:fundraiser, restaurant: restaurant, order_code: "")
      fundraiser.save(validate: false) # Save without validation to test the before_validation callback
      fundraiser.valid?
      expect(fundraiser.order_code).to be_present
    end
  end
end
