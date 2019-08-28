# this contains spaces to test the basic shell escaping
file '/tmp/guard target file' do
  action :create
end

# Check that arrays can be used as commands for safety against shells

remote_execute 'array command' do
  command ['touch', '/tmp/$something']
  user 'testuser'
  password node['test-cookbook']['testuser']['password']
  address 'localhost'
end

remote_execute 'array only_if_remote guard positive' do
  command ['touch', '/tmp/should-not-exist']
  user 'testuser'
  password node['test-cookbook']['testuser']['password']
  address 'localhost'
  only_if_remote ['test', '!', '-f', '/tmp/guard target file']
end

remote_execute 'array not_if_remote guard positive' do
  command ['touch', '/tmp/should-not-exist']
  user 'testuser'
  password node['test-cookbook']['testuser']['password']
  address 'localhost'
  not_if_remote ['test', '-f', '/tmp/guard target file']
end

remote_execute 'array only_if_remote guard negative' do
  command ['touch', '/tmp/only-if-array']
  user 'testuser'
  password node['test-cookbook']['testuser']['password']
  address 'localhost'
  only_if_remote ['test', '-f', '/tmp/guard target file']
end

remote_execute 'array not_if_remote guard negative' do
  command ['touch', '/tmp/not-if-array']
  user 'testuser'
  password node['test-cookbook']['testuser']['password']
  address 'localhost'
  not_if_remote ['test', '!', '-f', '/tmp/guard target file']
end
