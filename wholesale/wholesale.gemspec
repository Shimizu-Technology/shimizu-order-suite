require_relative "lib/wholesale/version"

Gem::Specification.new do |spec|
  spec.name        = "wholesale"
  spec.version     = Wholesale::VERSION
  spec.authors     = [ "Leon Shimizu" ]
  spec.email       = [ "lmshimizu@gmail.com" ]
  spec.homepage    = "https://github.com/hafaloha/wholesale"
  spec.summary     = "Wholesale fundraising engine for Hafaloha Order Management System."
  spec.description = "Rails engine providing wholesale fundraising functionality for multi-tenant restaurant order management system."

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the "allowed_push_host"
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/hafaloha/wholesale"
  spec.metadata["changelog_uri"] = "https://github.com/hafaloha/wholesale/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 7.2.2.1"
end
