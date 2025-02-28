require 'rails_helper'

RSpec.describe Restaurant, type: :model do
  describe 'associations' do
    it { should have_many(:users).dependent(:destroy) }
    it { should have_many(:reservations).dependent(:destroy) }
    it { should have_many(:waitlist_entries).dependent(:destroy) }
    it { should have_many(:menus).dependent(:destroy) }
    it { should have_many(:operating_hours).dependent(:destroy) }
    it { should have_many(:special_events).dependent(:destroy) }
    it { should have_many(:layouts).dependent(:destroy) }
    it { should have_many(:seat_sections).through(:layouts) }
    it { should have_many(:seats).through(:seat_sections) }
    it { should belong_to(:current_layout).class_name('Layout').optional }
  end

  describe 'validations' do
    it { should validate_presence_of(:time_zone) }
    it { should validate_numericality_of(:default_reservation_length).only_integer.is_greater_than(0) }
  end

  describe 'attributes' do
    it 'has allowed_origins as an array with default empty array' do
      restaurant = Restaurant.new
      expect(restaurant.allowed_origins).to eq([])
    end
  end

  describe '#add_allowed_origin' do
    let(:restaurant) { create(:restaurant, allowed_origins: []) }

    it 'adds a new origin to allowed_origins' do
      restaurant.add_allowed_origin('http://example.com')
      expect(restaurant.allowed_origins).to include('http://example.com')
    end

    it 'normalizes the origin by removing trailing slash' do
      restaurant.add_allowed_origin('http://example.com/')
      expect(restaurant.allowed_origins).to include('http://example.com')
      expect(restaurant.allowed_origins).not_to include('http://example.com/')
    end

    it 'does not add duplicate origins' do
      restaurant.add_allowed_origin('http://example.com')
      restaurant.add_allowed_origin('http://example.com')
      expect(restaurant.allowed_origins.count('http://example.com')).to eq(1)
    end

    it 'does nothing when origin is blank' do
      expect { restaurant.add_allowed_origin('') }.not_to change { restaurant.allowed_origins }
      expect { restaurant.add_allowed_origin(nil) }.not_to change { restaurant.allowed_origins }
    end
  end

  describe '#remove_allowed_origin' do
    let(:restaurant) { create(:restaurant, allowed_origins: ['http://example.com', 'http://test.com']) }

    it 'removes an origin from allowed_origins' do
      restaurant.remove_allowed_origin('http://example.com')
      expect(restaurant.allowed_origins).not_to include('http://example.com')
      expect(restaurant.allowed_origins).to include('http://test.com')
    end

    it 'normalizes the origin by removing trailing slash' do
      restaurant.remove_allowed_origin('http://example.com/')
      expect(restaurant.allowed_origins).not_to include('http://example.com')
    end

    it 'does nothing when origin is not in the list' do
      expect { restaurant.remove_allowed_origin('http://nonexistent.com') }.not_to change { restaurant.allowed_origins }
    end

    it 'does nothing when origin is blank' do
      expect { restaurant.remove_allowed_origin('') }.not_to change { restaurant.allowed_origins }
      expect { restaurant.remove_allowed_origin(nil) }.not_to change { restaurant.allowed_origins }
    end
  end

  describe '#current_seats' do
    context 'when current_layout is present' do
      let(:restaurant) { create(:restaurant) }
      let(:layout) { create(:layout, restaurant: restaurant) }
      let(:section) { create(:seat_section, layout: layout) }
      let!(:seats) { create_list(:seat, 3, seat_section: section) }

      before do
        restaurant.update(current_layout: layout)
      end

      it 'returns all seats from the current layout' do
        expect(restaurant.current_seats).to match_array(seats)
      end
    end

    context 'when current_layout is nil' do
      let(:restaurant) { create(:restaurant, current_layout: nil) }

      it 'returns an empty array' do
        expect(restaurant.current_seats).to eq([])
      end
    end
  end
end
