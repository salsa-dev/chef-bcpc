#
# Cookbook Name:: bcpc
# Recipe:: rally-deployments
#
# Copyright 2017, Bloomberg Finance L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Note: The rally.rb recipe must have already been executed before running this one.
# IMPORTANT: The head nodes MUST have already been installed and the keystone endpoints working. Rally verifies.

KEYSTONE_API_VERSIONS = %w{ v2.0 v3 }
rally_user = node['bcpc']['rally']['user']

# This json file represents the current deployment of OpenStack. It is read in a later section and then
# the information from the json file is created in Rally's database to be used for tests.
KEYSTONE_API_VERSIONS.each do |version|
  infile = File.join(Chef::Config[:file_cache_path], "rally-existing-#{version}.json")
  template "/var/chef/cache/rally-existing-#{version}.json" do
      user 'root'
      source "rally.existing.json.erb"
      owner rally_user
      group rally_user
      mode 0660
      variables(
        api_version: version,
        region_name:  node.chef_environment,
        username: get_config('keystone-admin-user'),
        password: get_config('keystone-admin-password'),
        project_name: node['bcpc']['admin_tenant'],
      )
  end
end

# Inits the db. If a db already exists then this command will init back to an empty-clean state
directory "/var/lib/rally/database" do
      owner rally_user
      group rally_user
      mode 0761
end

bash "rally-db-recreate" do
    user rally_user
    code <<-EOH
        rally-manage db recreate
    EOH
end

# Also required is a hostsfile (or DNS) entry for API endpoint hostname
hostsfile_entry "#{node['bcpc']['management']['vip']}" do
  hostname "openstack.#{node['bcpc']['cluster_domain']}"
  action :create_if_missing
end

# Setup two deployments, each corresponding to the keystone API versions
KEYSTONE_API_VERSIONS.each do |version|
  infile = File.join(Chef::Config[:file_cache_path], "rally-existing-#{version}.json")
  bash "rally-deployment-create-#{version}" do
      user rally_user
      code <<-EOH
          # Another approach is to use --fromenv...
          rally deployment create --file="#{infile}" --name=#{version}
          unlink "#{infile}"
      EOH
  end
end

# This will also setup keys that are probably not necessary...
include_recipe "bcpc::certs"
