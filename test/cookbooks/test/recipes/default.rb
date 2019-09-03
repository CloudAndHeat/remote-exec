include_recipe 'test::sshd'

testfiles = [
  'foo',
  'bar',
  'should-not-exist',
  'input',
  'not-if-ok',
  'not-if-smoke',
  'only-if-ok',
  '$something',
  'notify-before',
  'notify-before-not_if_remote',
  'notify-before-only_if_remote',
  'via-private-key',
  'multi-with-input',
  'multi-ssh-connection',
  'privileged',
  'privileged-guard-unconfigured',
  'unprivileged-guard-privileged',
]

testfiles.each do |f|
  file "/tmp/#{f}" do
    action :delete
  end
end

include_recipe 'test::simple'
include_recipe 'test::notifications_and_guards'
include_recipe 'test::ptytest'
include_recipe 'test::arrays'
include_recipe 'test::error_handling'
include_recipe 'test::become_user'
# include_recipe 'test::failing'
