package 'openssh-server'

service 'sshd' do
  action :start
end

user 'testuser' do
  manage_home true
  password '$6$HE5ZpCQpxjHXxpDW$CNagQeQnHemlWpd9Lq77KIeZIOpz4zgy5wJA3njHP6bVEq0kYYJuZ4fqgm/fUL5/KFD.3jr.Xma5VCq1Zwe.k.'
end

execute 'ssh-keygen -t rsa -f /root/.ssh/custom_id_rsa' do
  only_if 'test ! -f /root/.ssh/custom_id_rsa'
end

directory '/home/testuser/.ssh' do
  owner 'testuser'
  group 'testuser'
  mode 0o700
end

execute 'cp /root/.ssh/custom_id_rsa.pub /home/testuser/.ssh/authorized_keys'

file '/home/testuser/.ssh/authorized_keys' do
  owner 'testuser'
  group 'testuser'
  mode 0o600
end

sudo 'testuser' do
  user 'testuser'
  nopasswd true
end
