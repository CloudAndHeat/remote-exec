# Create a file which is then tested for in the inspec tests.
remote_execute 'touch /tmp/privileged' do
  user 'testuser'
  become_user 'root'
  password node['test-cookbook']['testuser']['password']
  address 'localhost'
end

remote_execute 'privileged-guard-unconfigured' do
  command ['true']
  user 'testuser'
  become_user 'root'
  password node['test-cookbook']['testuser']['password']
  address 'localhost'
  only_if_remote ['touch', '/tmp/privileged-guard-unconfigured']
end

remote_execute 'unprivileged-guard-privileged' do
  command ['true']
  user 'testuser'
  password node['test-cookbook']['testuser']['password']
  address 'localhost'
  only_if_remote command: ['touch', '/tmp/unprivileged-guard-privileged'], become_user: 'root'
end

remote_execute 'privileged-guard-unprivileged' do
  command ['true']
  user 'testuser'
  become_user 'root'
  password node['test-cookbook']['testuser']['password']
  address 'localhost'
  only_if_remote command: ['touch', '/tmp/privileged-guard-unprivileged'], become_user: user
end
