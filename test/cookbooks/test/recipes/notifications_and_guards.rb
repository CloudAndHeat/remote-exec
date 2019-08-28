# Check that not_if_remote prevents execution and is executed remotely
remote_execute 'not_if_remote test' do
  command 'touch /tmp/should-not-exist'
  user 'testuser'
  password node['test-cookbook']['testuser']['password']
  address 'localhost'
  not_if_remote '/usr/local/bin/is-local-ssh'
  stream_output false
end

# This should be created, because the not_if script should only work on remote
# links.
remote_execute 'touch /tmp/not-if-smoke' do
  user 'testuser'
  password node['test-cookbook']['testuser']['password']
  address 'localhost'
  not_if '/usr/local/bin/is-local-ssh'
  stream_output false
end

remote_execute 'touch /tmp/not-if-ok' do
  user 'testuser'
  password node['test-cookbook']['testuser']['password']
  address 'localhost'
  not_if_remote '/usr/local/bin/is-not-local-ssh'
  stream_output false
end

remote_execute 'touch /tmp/only-if-ok' do
  user 'testuser'
  password node['test-cookbook']['testuser']['password']
  address 'localhost'
  only_if_remote '/usr/local/bin/is-local-ssh'
  stream_output false
end

remote_execute 'only_if_remote test' do
  command 'touch /tmp/should-not-exist'
  user 'testuser'
  password node['test-cookbook']['testuser']['password']
  address 'localhost'
  only_if_remote '/usr/local/bin/is-not-local-ssh'
  stream_output false
end

# Check that both not_if_remote and only_if_remote are taken into account

remote_execute 'not_if_remote plus only_if_remote test variant 1' do
  command 'touch /tmp/should-not-exist'
  user 'testuser'
  password node['test-cookbook']['testuser']['password']
  address 'localhost'
  not_if_remote 'true' # forbids execution
  only_if_remote 'true'  # allows execution
  stream_output false
end

remote_execute 'not_if_remote plus only_if_remote test variant 2' do
  command 'touch /tmp/should-not-exist'
  user 'testuser'
  password node['test-cookbook']['testuser']['password']
  address 'localhost'
  not_if_remote 'false'  # allows execution
  only_if_remote 'false' # forbids execution
  stream_output false
end

# Check that remote guard evaluation blocks notifications
remote_execute 'not_if_remote blocks following notifications' do
  command 'touch /tmp/should-not-exist'
  user 'testuser'
  address 'localhost'
  password node['test-cookbook']['testuser']['password']
  not_if_remote 'true'
  notifies :create, 'file[/tmp/should-not-exist]', :immediately
end

remote_execute 'only_if_remote blocks following notifications' do
  command 'touch /tmp/should-not-exist'
  user 'testuser'
  address 'localhost'
  password node['test-cookbook']['testuser']['password']
  only_if_remote 'false'
  notifies :create, 'file[/tmp/should-not-exist]', :immediately
end

remote_execute 'not_if_remote blocks before notifications' do
  command 'touch /tmp/should-not-exist'
  user 'testuser'
  address 'localhost'
  password node['test-cookbook']['testuser']['password']
  not_if_remote 'true'
  notifies :create, 'file[/tmp/should-not-exist]', :before
end

remote_execute 'only_if_remote blocks before notifications' do
  command 'touch /tmp/should-not-exist'
  user 'testuser'
  address 'localhost'
  password node['test-cookbook']['testuser']['password']
  only_if_remote 'false'
  notifies :create, 'file[/tmp/should-not-exist]', :before
end

remote_execute 'not_if_remote and only_if_remote block following notifications for multiple targets' do
  command 'touch /tmp/should-not-exist'
  user 'testuser'
  address((1..2).map { |x| "127.1.0.#{x}" })
  password node['test-cookbook']['testuser']['password']
  password node['test-cookbook']['testuser']['password']
  not_if_remote 'echo $SSH_CONNECTION | grep 127.1.0.2'
  only_if_remote 'echo $SSH_CONNECTION | grep -v 127.1.0.1'
  notifies :create, 'file[/tmp/should-not-exist]', :immediately
end

# Check successful before notifications
remote_execute 'with before notification' do
  command 'test -f /tmp/notify-before'
  user 'testuser'
  address 'localhost'
  password node['test-cookbook']['testuser']['password']
  notifies :create, 'file[/tmp/notify-before]', :before
end

remote_execute 'only_if_remote with before notification' do
  command 'test -f /tmp/notify-before-only_if_remote'
  user 'testuser'
  address 'localhost'
  password node['test-cookbook']['testuser']['password']
  only_if_remote 'true'
  notifies :create, 'file[/tmp/notify-before-only_if_remote]', :before
end

remote_execute 'not_if_remote with before notification' do
  command 'test -f /tmp/notify-before-not_if_remote'
  user 'testuser'
  address 'localhost'
  password node['test-cookbook']['testuser']['password']
  not_if_remote 'false'
  notifies :create, 'file[/tmp/notify-before-not_if_remote]', :before
end
