# config/initializers/tenant_isolation_patch.rb
#
# Legacy production monkey patches were removed. Tenant access rules now live in
# TenantIsolation and the controllers themselves so authentication, tenant
# resolution, and public endpoint exceptions are consistent across environments.
