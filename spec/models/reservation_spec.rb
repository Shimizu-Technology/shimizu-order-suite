require 'rails_helper'

RSpec.describe Reservation, type: :model do
  describe 'associations' do
    it { should belong_to(:restaurant) }
  end

  describe 'validations' do
    it 'validates status is one of the allowed values' do
      reservation = build(:reservation)
      
      # Valid statuses
      %w[booked reserved seated finished canceled no_show].each do |status|
        reservation.status = status
        expect(reservation).to be_valid
      end
      
      # Invalid status
      reservation.status = 'invalid_status'
      expect(reservation).not_to be_valid
    end
  end

  describe 'defaults' do
    it 'has default status of booked' do
      reservation = Reservation.new
      expect(reservation.status).to eq('booked')
    end

    it 'has default party_size of 1' do
      reservation = Reservation.new
      expect(reservation.party_size).to eq(1)
    end

    it 'has default reservation_source of online' do
      reservation = Reservation.new
      expect(reservation.reservation_source).to eq('online')
    end

    it 'has default seat_preferences as an empty array' do
      reservation = Reservation.new
      expect(reservation.seat_preferences).to eq([])
    end

    it 'has default duration_minutes of 60' do
      reservation = Reservation.new
      expect(reservation.duration_minutes).to eq(60)
    end
  end

  describe 'scopes and queries' do
    let(:restaurant) { create(:restaurant) }
    let!(:booked_reservation) { create(:reservation, restaurant: restaurant, status: 'booked') }
    let!(:seated_reservation) { create(:reservation, restaurant: restaurant, status: 'seated') }
    let!(:finished_reservation) { create(:reservation, restaurant: restaurant, status: 'finished') }
    let!(:canceled_reservation) { create(:reservation, restaurant: restaurant, status: 'canceled') }
    let!(:no_show_reservation) { create(:reservation, restaurant: restaurant, status: 'no_show') }
    
    # Add scopes as they are defined in the model
    # For example:
    # 
    # describe '.active' do
    #   it 'returns only booked and seated reservations' do
    #     active_reservations = Reservation.active
    #     expect(active_reservations).to include(booked_reservation, seated_reservation)
    #     expect(active_reservations).not_to include(finished_reservation, canceled_reservation, no_show_reservation)
    #   end
    # end
  end

  describe 'callbacks' do
    # Add tests for any callbacks defined in the model
  end

  describe 'instance methods' do
    # Add tests for any instance methods defined in the model
  end

  describe 'seat allocations' do
    let(:restaurant) { create(:restaurant) }
    let(:layout) { create(:layout, restaurant: restaurant) }
    let(:section) { create(:seat_section, layout: layout) }
    let(:seat) { create(:seat, seat_section: section) }
    let(:reservation) { create(:reservation, restaurant: restaurant) }
    
    it 'can have seat allocations' do
      allocation = create(:seat_allocation, reservation: reservation, seat: seat)
      expect(reservation.seat_allocations).to include(allocation)
    end
  end
end
