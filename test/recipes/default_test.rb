describe file('/tmp/foo') do
  it { should exist }
  its('owner') { should eq 'testuser' }
  its('group') { should eq 'testuser' }
end

describe file('/tmp/input') do
  it { should exist }
  its('content') { should eq "some test input, even with funny characters like \" and '." }
end

describe file('/tmp/should-not-exist') do
  it { should_not exist }
end

describe file('/tmp/only-if-ok') do
  it { should exist }
end

describe file('/tmp/not-if-ok') do
  it { should exist }
end

describe file('/tmp/not-if-smoke') do
  it { should exist }
end

describe file('/tmp/notify-before') do
  it { should exist }
end

describe file('/tmp/notify-before-only_if_remote') do
  it { should exist }
end

describe file('/tmp/notify-before-not_if_remote') do
  it { should exist }
end

describe file('/tmp/$something') do
  it { should exist }
end

describe file('/tmp/not-if-array') do
  it { should exist }
end

describe file('/tmp/only-if-array') do
  it { should exist }
end

describe file('/tmp/via-private-key') do
  it { should exist }
end

describe file('/tmp/multi-with-input') do
  it { should exist }
  its('content') { should eq "input line\ninput line\n" }
end

describe file('/tmp/multi-ssh-connection') do
  it { should exist }
  its('content') { should include '127.1.0.1' }
  its('content') { should_not include '127.1.0.2' }
  its('content') { should_not include '127.1.0.3' }
  its('content') { should include '127.1.0.4' }
  its('content') { should_not include '127.1.0.5' }
  its('content') { should include '127.1.0.6' }
  its('content') { should_not include '127.1.0.7' }
  its('content') { should include '127.1.0.8' }
  its('content') { should_not include '127.1.0.9' }
  its('content') { should_not include '127.1.0.10' }
end

describe file('/tmp/privileged') do
  it { should exist }
  its('owner') { should eq 'root' }
  its('group') { should eq 'root' }
end

describe file('/tmp/privileged-guard-unconfigured') do
  it { should exist }
  its('owner') { should eq 'root' }
  its('group') { should eq 'root' }
end

describe file('/tmp/unprivileged-guard-privileged') do
  it { should exist }
  its('owner') { should eq 'root' }
  its('group') { should eq 'root' }
end

describe file('/tmp/privileged-guard-unprivileged') do
  it { should exist }
  its('owner') { should eq 'testuser' }
  its('group') { should eq 'testuser' }
end
