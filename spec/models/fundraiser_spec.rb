require 'rails_helper'

RSpec.describe Fundraiser, type: :model do
  describe 'scopes' do
    let(:restaurant) { create(:restaurant) }
    let!(:active_fundraiser) { create(:fundraiser, restaurant: restaurant, active: true, start_date: 1.day.ago, end_date: 1.day.from_now) }
    let!(:inactive_fundraiser) { create(:fundraiser, restaurant: restaurant, active: false, start_date: 1.day.ago, end_date: 1.day.from_now) }
    let!(:past_fundraiser) { create(:fundraiser, restaurant: restaurant, active: true, start_date: 3.days.ago, end_date: 1.day.ago) }
    let!(:future_fundraiser) { create(:fundraiser, restaurant: restaurant, active: true, start_date: 1.day.from_now, end_date: 3.days.from_now) }
    
    # The key test for our indefinite fundraiser implementation
    let!(:indefinite_fundraiser) { create(:fundraiser, restaurant: restaurant, active: true, start_date: 1.day.ago, end_date: nil) }
    let!(:null_start_date_fundraiser) { create(:fundraiser, restaurant: restaurant, active: true, start_date: nil, end_date: 1.day.from_now) }
    let!(:both_null_dates_fundraiser) { create(:fundraiser, restaurant: restaurant, active: true, start_date: nil, end_date: nil) }
    
    describe '.active' do
      it 'returns only active fundraisers' do
        expect(Fundraiser.active).to include(active_fundraiser, past_fundraiser, future_fundraiser, indefinite_fundraiser, null_start_date_fundraiser, both_null_dates_fundraiser)
        expect(Fundraiser.active).not_to include(inactive_fundraiser)
      end
    end
    
    describe '.current' do
      it 'returns active fundraisers within date range' do
        current_fundraisers = Fundraiser.current
        
        expect(current_fundraisers).to include(active_fundraiser)
        expect(current_fundraisers).not_to include(inactive_fundraiser)
        expect(current_fundraisers).not_to include(past_fundraiser)
        expect(current_fundraisers).not_to include(future_fundraiser)
      end
      
      it 'includes indefinite fundraisers (null end_date)' do
        expect(Fundraiser.current).to include(indefinite_fundraiser)
      end
      
      it 'includes fundraisers with null start_date that have not ended' do
        expect(Fundraiser.current).to include(null_start_date_fundraiser)
      end
      
      it 'includes fundraisers with both null dates if active' do
        expect(Fundraiser.current).to include(both_null_dates_fundraiser)
      end
    end
  end
  
  describe 'validations' do
    it 'validates presence of name' do
      fundraiser = build(:fundraiser, name: nil)
      expect(fundraiser).not_to be_valid
      expect(fundraiser.errors[:name]).to include("can't be blank")
    end
    
    it 'validates presence of slug' do
      fundraiser = build(:fundraiser, slug: nil)
      expect(fundraiser).not_to be_valid
      expect(fundraiser.errors[:slug]).to include("can't be blank")
    end
    
    it 'allows null start_date' do
      fundraiser = build(:fundraiser, start_date: nil)
      expect(fundraiser).to be_valid
    end
    
    it 'allows null end_date for indefinite fundraisers' do
      fundraiser = build(:fundraiser, end_date: nil)
      expect(fundraiser).to be_valid
    end
  end
  
  describe 'callbacks' do
    it 'normalizes slug before validation' do
      fundraiser = build(:fundraiser, slug: 'Test Slug')
      fundraiser.valid?
      expect(fundraiser.slug).to eq('test-slug')
    end
  end
end
