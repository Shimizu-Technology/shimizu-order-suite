require 'rails_helper'

RSpec.describe FundraiserCounter, type: :model do
  describe "validations" do
    it { should validate_presence_of(:counter_value) }
    it { should validate_presence_of(:restaurant_id) }
    it { should validate_presence_of(:fundraiser_id) }
    it { should validate_numericality_of(:counter_value).only_integer.is_greater_than_or_equal_to(0) }
    
    it "validates uniqueness of fundraiser_id scoped to restaurant_id" do
      # Create a fundraiser counter
      fundraiser_counter = create(:fundraiser_counter)
      
      # Try to create another counter with the same restaurant and fundraiser
      duplicate = build(:fundraiser_counter, 
        restaurant: fundraiser_counter.restaurant, 
        fundraiser: fundraiser_counter.fundraiser
      )
      
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:fundraiser_id]).to include("has already been taken")
    end
  end
  
  describe "associations" do
    it { should belong_to(:restaurant) }
    it { should belong_to(:fundraiser) }
  end
end
