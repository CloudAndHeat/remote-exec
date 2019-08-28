cookbook_file '/usr/local/bin/is-local-ssh' do
  source 'is-local-ssh.sh'
  mode 0o755
  owner 'root'
  group 'root'
end

cookbook_file '/usr/local/bin/is-not-local-ssh' do
  source 'is-not-local-ssh.sh'
  mode 0o755
  owner 'root'
  group 'root'
end

# Create a file which is then tested for in the inspec tests.
remote_execute 'touch /tmp/foo' do
  user 'testuser'
  password node['test-cookbook']['testuser']['password']
  address 'localhost'
end

# Check that a non-zero exit status can be masked via array
remote_execute 'false' do
  user 'testuser'
  password node['test-cookbook']['testuser']['password']
  address 'localhost'
  returns [1]
end

# Check that a non-zero exit status can be masked via value
remote_execute 'false' do
  user 'testuser'
  password node['test-cookbook']['testuser']['password']
  address 'localhost'
  returns 1
end

# Check that input can be passed to the remote; the inspec test will check the
# contents
remote_execute 'tee /tmp/input' do
  user 'testuser'
  password node['test-cookbook']['testuser']['password']
  address 'localhost'
  input "some test input, even with funny characters like \" and '."
  live_stream true
end

# Check that output on stderr does not break anything (#4)

remote_execute 'non-existant-command' do
  user 'testuser'
  password node['test-cookbook']['testuser']['password']
  address 'localhost'
  returns 127
end

# Check that action :nothing does nothing

remote_execute 'touch /tmp/should-not-exist' do
  action :nothing
  user 'testuser'
  password node['test-cookbook']['testuser']['password']
  address 'localhost'
end

# Check that EOF is always sent. The following resource would timeout otherwise.
remote_execute 'cat' do
  user 'testuser'
  password node['test-cookbook']['testuser']['password']
  address 'localhost'
end

# Check passing the private key via options
remote_execute 'touch /tmp/via-private-key' do
  user 'testuser'
  address 'localhost'
  options(
    :keys => ['/root/.ssh/custom_id_rsa'],
    :keys_only => true
  )
end

# Various checks around concurrency

remote_execute 'tee -a /tmp/multi-with-input' do
  user 'testuser'
  address ['127.0.0.1', '127.0.0.10']
  password node['test-cookbook']['testuser']['password']
  input "input line\n"
  live_stream true
end

# Check that guards are evaluated independently (the InSpec check verifies the
# content of the file)
remote_execute 'echo "$SSH_CONNECTION" | tee -a /tmp/multi-ssh-connection > /dev/null' do
  user 'testuser'
  address((1..10).map { |x| "127.1.0.#{x}" })
  password node['test-cookbook']['testuser']['password']
  not_if_remote 'echo $SSH_CONNECTION | grep 127.1.0.2'
  only_if_remote 'echo $SSH_CONNECTION | grep -P "127\.1\.0\.([2468]|1[^0])"'
  live_stream true
end
