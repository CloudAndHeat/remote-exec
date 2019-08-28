remote_execute 'command failure, no streaming, no sensitive' do
  command 'echo foo; echo bar >&2; false'
  address 'localhost'
  user 'testuser'
  password node['test-cookbook']['testuser']['password']
  ignore_failure true
end

remote_execute 'command failure, no streaming, sensitive output' do
  command 'echo foo; echo bar >&2; false'
  address 'localhost'
  user 'testuser'
  password node['test-cookbook']['testuser']['password']
  ignore_failure true
  sensitive_output true
end

remote_execute 'command failure, no streaming, sensitive command' do
  command 'echo foo; echo bar >&2; false'
  address 'localhost'
  user 'testuser'
  password node['test-cookbook']['testuser']['password']
  ignore_failure true
  sensitive_command true
end

remote_execute 'command failure, streaming, sensitive command' do
  command 'echo foo; echo bar >&2; false'
  address 'localhost'
  user 'testuser'
  live_stream true
  password node['test-cookbook']['testuser']['password']
  ignore_failure true
  sensitive_command true
end

remote_execute 'command failure, streaming, sensitive output' do
  command 'echo foo; echo bar >&2; false'
  address 'localhost'
  user 'testuser'
  live_stream true
  password node['test-cookbook']['testuser']['password']
  ignore_failure true
  sensitive_output true
end
