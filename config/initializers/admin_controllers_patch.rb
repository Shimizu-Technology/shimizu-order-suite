# config/initializers/admin_controllers_patch.rb
#
# Legacy production monkey patches were removed. Admin access is enforced by the
# relevant controllers and TenantIsolation after current_user has been loaded.
