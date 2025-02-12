# config/initializers/auth0_jwt.rb
require 'net/http'
require 'uri'
require 'openssl'
require 'jwt'

# Load environment variables (dotenv will handle this if you're using dotenv-rails)
AUTH0_DOMAIN    = ENV['AUTH0_DOMAIN']    || 'dev-XXXX.us.auth0.com'
AUTH0_ISSUER    = "https://#{AUTH0_DOMAIN}/"
AUTH0_AUDIENCE  = ENV['AUTH0_AUDIENCE'] || 'https://api.hafaloha.com'
JWKS_URI        = URI("https://#{AUTH0_DOMAIN}/.well-known/jwks.json")

def fetch_jwks_keys
  jwks_raw = Net::HTTP.get(JWKS_URI)
  JSON.parse(jwks_raw)['keys']
end

def find_jwk(kid)
  @auth0_jwks ||= fetch_jwks_keys
  key_hash = @auth0_jwks.find { |k| k['kid'] == kid }
  raise "JWK not found for kid: #{kid}" unless key_hash
  key_hash
end

def verify_auth0_token(token)
  # decode header first to find kid
  # or decode the entire token w/ nil key first to get the header
  header_segment = JWT.decode(token, nil, false)[1] 
  kid = header_segment['kid']

  jwk       = find_jwk(kid)
  public_key = OpenSSL::PKey::RSA.new(JWT::JWK::RSA.import(jwk).public_key)

  decoded, _ = JWT.decode(token, public_key, true, {
    algorithm: 'RS256',
    iss: AUTH0_ISSUER,
    verify_iss: true,
    aud: AUTH0_AUDIENCE,
    verify_aud: true
  })

  decoded
end
