# spec/middleware/tenant_validation_middleware_spec.rb
require 'rails_helper'

RSpec.describe TenantValidationMiddleware do
  let(:app) { ->(env) { [200, env, ['OK']] } }
  let(:middleware) { described_class.new(app) }
  let(:restaurant) { create(:restaurant) }
  let(:user) { create(:user, restaurant: restaurant) }
  let(:token) { TokenService.generate_token(user) }
  
  describe '#call' do
    context 'with public endpoints' do
      it 'allows access to health endpoint' do
        env = { 'PATH_INFO' => '/health' }
        status, _, _ = middleware.call(env)
        expect(status).to eq(200)
      end
      
      it 'allows access to static assets' do
        env = { 'PATH_INFO' => '/assets/application.js' }
        status, _, _ = middleware.call(env)
        expect(status).to eq(200)
      end
      
      it 'allows access to login endpoint' do
        env = { 'PATH_INFO' => '/api/v1/sessions' }
        status, _, _ = middleware.call(env)
        expect(status).to eq(200)
      end
    end
    
    context 'with valid tenant context' do
      it 'allows access with valid JWT token' do
        env = { 
          'PATH_INFO' => '/api/v1/users',
          'HTTP_AUTHORIZATION' => "Bearer #{token}"
        }
        status, _, _ = middleware.call(env)
        expect(status).to eq(200)
      end
      
      it 'allows access with restaurant_id in params' do
        env = { 
          'PATH_INFO' => '/api/v1/menus',
          'QUERY_STRING' => "restaurant_id=#{restaurant.id}",
          'rack.input' => StringIO.new
        }
        status, _, _ = middleware.call(env)
        expect(status).to eq(200)
      end
    end
    
    context 'with invalid tenant context' do
      it 'rejects access with invalid restaurant_id in JWT token' do
        invalid_token = JWT.encode(
          { user_id: user.id, restaurant_id: 999999 }, 
          Rails.application.secret_key_base
        )
        
        env = { 
          'PATH_INFO' => '/api/v1/users',
          'HTTP_AUTHORIZATION' => "Bearer #{invalid_token}"
        }
        
        allow(Restaurant).to receive(:exists?).with(999999).and_return(false)
        
        status, _, body = middleware.call(env)
        expect(status).to eq(403)
        expect(JSON.parse(body.first)['error']).to eq('Invalid tenant context')
      end
    end
    
    context 'with rate limiting' do
      it 'rejects access when rate limit is exceeded' do
        env = { 
          'PATH_INFO' => '/api/v1/users',
          'HTTP_AUTHORIZATION' => "Bearer #{token}"
        }
        
        # Mock Redis to simulate rate limit exceeded
        redis_mock = double('Redis')
        allow(Redis).to receive(:new).and_return(redis_mock)
        allow(redis_mock).to receive(:incr).and_return(101) # Over the default limit of 100
        allow(redis_mock).to receive(:expire)
        
        status, _, body = middleware.call(env)
        expect(status).to eq(429)
        expect(JSON.parse(body.first)['error']).to eq('Rate limit exceeded')
      end
    end
  end
end
