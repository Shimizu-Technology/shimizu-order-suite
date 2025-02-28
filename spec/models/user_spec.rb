require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'associations' do
    it { should belong_to(:restaurant).optional }
  end

  describe 'validations' do
    it { should validate_presence_of(:email) }
    it { should validate_uniqueness_of(:email).case_insensitive }
    it { should validate_presence_of(:first_name) }
    it { should validate_presence_of(:last_name) }
    
    context 'when not skipping password validation' do
      it { should validate_presence_of(:password_digest) }
    end
    
    context 'when skipping password validation' do
      before do
        allow_any_instance_of(User).to receive(:skip_password_validation).and_return(true)
      end
      
      it { should_not validate_presence_of(:password_digest) }
    end
  end

  describe 'callbacks' do
    it 'downcases email before saving' do
      user = build(:user, email: 'TEST@EXAMPLE.COM')
      user.save
      expect(user.email).to eq('test@example.com')
    end
  end

  describe '#full_name' do
    it 'returns the combined first and last name' do
      user = build(:user, first_name: 'John', last_name: 'Doe')
      expect(user.full_name).to eq('John Doe')
    end
  end

  describe '#admin?' do
    it 'returns true when role is admin' do
      user = build(:user, role: 'admin')
      expect(user.admin?).to be true
    end

    it 'returns false when role is not admin' do
      user = build(:user, role: 'customer')
      expect(user.admin?).to be false
    end
  end

  describe 'password reset' do
    let(:user) { create(:user) }

    describe '#generate_reset_password_token!' do
      it 'generates a reset password token and timestamp' do
        expect { user.generate_reset_password_token! }.to change { user.reset_password_token }.from(nil)
        expect(user.reset_password_sent_at).not_to be_nil
      end

      it 'returns a raw token' do
        raw_token = user.generate_reset_password_token!
        expect(raw_token).to be_a(String)
        expect(raw_token.length).to eq(20) # 10 bytes in hex = 20 chars
      end
    end

    describe '#reset_token_valid?' do
      let(:raw_token) { user.generate_reset_password_token! }

      it 'returns true for a valid token within time window' do
        expect(user.reset_token_valid?(raw_token)).to be true
      end

      it 'returns false for an invalid token' do
        expect(user.reset_token_valid?('invalid_token')).to be false
      end

      it 'returns false when token is expired' do
        user.update(reset_password_sent_at: 3.hours.ago)
        expect(user.reset_token_valid?(raw_token)).to be false
      end
    end

    describe '#clear_reset_password_token!' do
      before { user.generate_reset_password_token! }

      it 'clears the reset password token and timestamp' do
        expect { user.clear_reset_password_token! }.to change { user.reset_password_token }.to(nil)
        expect(user.reset_password_sent_at).to be_nil
      end
    end
  end
end
