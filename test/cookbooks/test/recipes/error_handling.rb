remote_execute 'do not timeout on auth errors' do
  address 'localhost'
  user 'foo'
  command 'true'
  ignore_failure true
end

remote_execute 'do not timeout on auth errors during not_if_remote' do
  address 'localhost'
  user 'foo'
  command 'true'
  not_if_remote 'true'
  ignore_failure true
end

remote_execute 'do not timeout on auth errors during only_if_remote' do
  address 'localhost'
  user 'foo'
  command 'true'
  only_if_remote 'true'
  ignore_failure true
end
