# Copyright:: Copyright 2016, eNFence GmbH
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'net/ssh/multi'

resource_name :remote_execute
default_action :run

property :command, [String, Array], name_property: true, required: true
property :returns, Array, default: [0], coerce: proc { |v| v.is_a?(Integer) ? [v] : v }, callbacks: {
  'must be Array of Integers' => ->(a) { a.all? { |v| v.is_a?(Integer) } },
}
property :timeout, Integer, default: 60
property :user, String
property :password, String, sensitive: true
property :address, Array, required: true, coerce: proc { |v| v.is_a?(String) ? [v] : v }, callbacks: {
  'must be Array of Strings' => ->(a) { a.all? { |v| v.is_a?(String) } },
}
property :input, String
property :interactive, [TrueClass, FalseClass], default: false
property :request_pty, [TrueClass, FalseClass], default: false
property :sensitive_output, [TrueClass, FalseClass], default: lazy { sensitive }
property :sensitive_command, [TrueClass, FalseClass], default: lazy { sensitive }
property :live_stream, [TrueClass, FalseClass], default: false
property :max_buffer_size, Integer, default: lazy {
  base_limit = 1048576
  max_concurrency = concurrent_connections
  max_concurrency = address.length if max_concurrency.nil? || address.length < max_concurrency
  max_concurrency = 1 if max_concurrency < 1
  base_limit / max_concurrency
}
property :max_line_length, Integer, default: 4096 # 4 kiB
property :options, Hash, coerce: proc { |v| RemoteExec::Validation.symbolize_options(v) }
property :concurrent_connections, Integer, callbacks: {
  'must be positive Integer' => ->(v) { v >= 1 },
}
property :max_connection_retries, Integer, default: 3
property :print_summary, [TrueClass, FalseClass], default: lazy { address.length > 1 || !live_stream }

property :become_user, String, default: lazy { user }

property :not_if_remote, [String, Array, Hash], coerce: proc { |v| RemoteExec::Validation.coerce_guard_config(v, sensitive) }, callbacks: RemoteExec::Validation.guard_config_checks
property :only_if_remote, [String, Array, Hash], coerce: proc { |v| RemoteExec::Validation.coerce_guard_config(v, sensitive) }, callbacks: RemoteExec::Validation.guard_config_checks

action :run do
  Chef::Log.debug('remote_execute.rb: action_run')

  command_options = {
    input: new_resource.input,
    request_pty: new_resource.request_pty,
  }

  if !new_resource.input.nil? && command_options.fetch(:request_pty)
    # XXX: IF we ever allow input with PTYs, the .eof! method used below will
    # not work. Instead, we have to send double-\x04 (Ctrl+D a.k.a. End Of
    # Tranmission ASCII control code) to signal EOF. This is all super-fragile
    # which is why it is prohibited for now.
    raise 'PTY requested for command execution, but input is given. The options are incompatible, as PTYs are not binary-safe.'
  end

  prepared_command = prepare_command(
    new_resource.command,
    new_resource.user,
    new_resource.become_user
  )

  ssh_session do |session|
    remaining_servers = evaluate_remote_guards(session)

    # If there are no servers left, we have to break out here; otherwise, there
    # is a converge_by block in the execution path, which causes the resource to
    # be "changed". That, in turn, triggers unwanted notifications.
    break if remaining_servers.empty?

    messages = ["execute #{formatter.masked_command(prepared_command, new_resource.sensitive_command)} on server #{remaining_servers.map(&:host)} as #{new_resource.user.inspect}"]
    converge_by(messages) do
      subsession = session.on(*remaining_servers)
      result_items = if new_resource.live_stream
                       ssh_exec_streamed(subsession,
                                         prepared_command,
                                         sensitive_output: new_resource.sensitive_output,
                                         sensitive_command: new_resource.sensitive_command,
                                         **command_options)
                     else
                       ssh_exec(subsession, prepared_command, command_options)
                     end

      error_parts = formatter.compose_exception_message(
        result_items,
        prepared_command,
        new_resource.sensitive_command,
        new_resource.sensitive_output,
        new_resource.returns
      )

      unless error_parts.empty?
        error_parts.insert(0, 'Remote process execution failed for one or more targets')
        raise error_parts.join("\n")
      end

      result_items.each_pair do |server, result_item|
        if new_resource.print_summary
          messages.push("  #{server.host}: #{result_item.state_to_s}")
        end
      end
    end
  end
end

action_class do
  def formatter
    @formatter ||= RemoteExec::Formatter.new
  end

  def prepare_command(command, login_user, become_user)
    command = flatten_command(command)
    if login_user != become_user
      command = "sudo -u #{Shellwords.escape(become_user)} #{command}"
    end
    command
  end

  def flatten_command(command)
    # Unfortunately, SSH does not allow passing an execv-like array and only
    # supports strings. So we have to do shell escaping and hope for the best...
    return command if command.is_a?(String)
    Shellwords.shelljoin(command)
  end

  # Evaluate the remote guards
  #
  # Execute the not_if_remote and only_if_remote guards (if applicable) on all
  # servers in the given session.
  #
  # Return the list of servers which have *not* been filtered out by the guards.
  #
  # If a server fails to connects, an exception is raised.
  def evaluate_remote_guards(session)
    remaining_servers = session.servers
    remaining_servers = evaluate_single_remote_guard(session.on(*remaining_servers), :not_if_remote)
    remaining_servers = evaluate_single_remote_guard(session.on(*remaining_servers), :only_if_remote)
    remaining_servers
  end

  # Evaluate a single remote guard and return the list of passed servers
  #
  # The `which_guard` argument determines which guard is evaluated, and it needs
  # to be the property symbol. The evaluation of the command return code is
  # adapted to the specific guard.
  #
  # Return a list of servers which have passed the guard check.
  def evaluate_single_remote_guard(session, which_guard)
    raise 'invalid guard type' unless [:not_if_remote, :only_if_remote].include?(which_guard)
    return session.servers unless property_is_set?(which_guard)
    guard_command_config = new_resource.send(which_guard)

    prepared_command = prepare_command(
      guard_command_config.fetch(:command),
      new_resource.user,
      guard_command_config[:become_user] || new_resource.become_user
    )

    passed_servers = filter_servers_by_result(session,
                                              prepared_command,
                                              request_pty: guard_command_config.fetch(:request_pty)
                                             ) do |srv, result_item|
      # this block needs to return true if we want to keep the server
      check_result = result_item.ok?([0])
      check_result = !check_result if which_guard == :not_if_remote
      Chef::Log.debug("server #{srv} excluded in #{which_guard} with result #{result_item.inspect}") unless check_result
      check_result
    end

    # all servers filtered, early out
    return [] if passed_servers.empty?

    Chef::Log.debug("#{new_resource}: evaluated #{which_guard} guard #{formatter.masked_command(prepared_command, guard_command_config.fetch(:sensitive_command))}: remaining servers #{passed_servers.map(&:host)}")

    passed_servers
  end

  # Execute a command on all servers and filter the server list by the result.
  #
  # Needs a block. The block is passed the server and the result item (which is
  # a hash which has :exit_code and :exit_status keys). The block is expected
  # to return true for those servers which should be kept and false for those
  # which should be excluded.
  #
  # Return the filtered list of servers.
  def filter_servers_by_result(session, command, options)
    result = ssh_exec(session, command, options)
    raise_connection_errors(result)

    # return only those servers for which the passed block returns true
    result.map do |srv, result_item|
      next srv if yield [srv, result_item]
      nil
    end.compact
  end

  # Set a key in hash to value if and only if the key is not already in hash.
  #
  # If the key is in hash and the value in the hash differs from the given
  # value, an error is raised.
  def set_if_unset!(hash, key, property, value)
    if hash.key?(key)
      raise "conflicting values set for property #{property} and options key #{key}" if property_is_set?(property) && hash[key] != value
    else
      hash[key] = value
    end
  end

  # Policy function which describes how connection errors are handled.
  #
  # This counts the number of connection attempts and aborts the connection
  # attempts when those are exceeded, after setting a "failed" flag on the
  # affected server.
  #
  # The failed flag is later collected by the ssh_exec / ssh_exec_streamed
  # functions and interpreted by raise_connection_errors.
  #
  # See also: Net::SSH::Multi::Session#on_error.
  def error_handler(server)
    server[:connection_attempts] ||= 0
    server[:connection_attempts] += 1
    if server[:connection_attempts] > new_resource.max_connection_retries
      server[:connection_failed] = true
      return
    end
    Chef::Log.warn("failed to connect via SSH to #{server}, re-trying ... (#{server[:connection_attempts]}/#{new_resource.max_connection_retries})")
    throw :go, :retry
  end

  # Raise an exception if any of the result items in the first argument have the
  # `connection_failed` flag set.
  #
  # In general, it is preferable to raise an error which lists all failed host
  # instead of failing on the first one. This function is thus only used during
  # guard processing.
  def raise_connection_errors(result_items)
    result_items.each do |srv, result_item|
      raise "Failed to connect to #{srv.user}@#{srv.host}" if result_item.connection_failed
    end
  end

  # Execute a block with an SSH session.
  #
  # Takes a block.
  #
  # A Net::SSH::Multi session is set up according to the resource’s properties
  # and yielded to the block. The return value of the block is returned by this
  # function.
  def ssh_session
    if property_is_set?(:options)
      options = new_resource.options.dup
      set_if_unset!(options, :password, :password, new_resource.password)
      set_if_unset!(options, :non_interactive, :interactive, !new_resource.interactive)
      set_if_unset!(options, :timeout, :timeout, new_resource.timeout)
    else
      options = {
        timeout: new_resource.timeout,
        non_interactive: !new_resource.interactive,
        password: new_resource.password,
      }
    end

    retval = nil
    multi_options = {
      on_error: proc { |server| error_handler(server) },
    }
    multi_options[:concurrent_connections] = new_resource.concurrent_connections if property_is_set?(:concurrent_connections)
    Net::SSH::Multi.start(multi_options) do |session|
      new_resource.address.each do |addr|
        session.use addr, user: new_resource.user, **options
      end

      retval = yield session
    end
    retval
  end

  # Execute a command on all hosts in a session, providing output and return
  # codes.
  #
  # `on_complete` must be a Proc which is called with two arguments (the server
  # and the a hash which has the :exit_code and the :exit_signal keys set) once
  # the command completes on the remote server.
  #
  # Any pieces of output sent on stdout or stderr of the command are yielded
  # to the passed block. The block receives three arguments: the channel object,
  # the stream (either :stdout or :stderr) and the block of data received.
  #
  # This function does not do any line-buffering.
  #
  # Careful! This returns a Net::SSH::Multi::Channel, but invoking `wait` on it
  # is not safe because of connection limits: if the server channel has not been
  # instantiated yet, `wait` returns immediately.
  def exec_io(session, command, on_complete, input: nil, request_pty: false)
    command = flatten_command(command)

    session.open_channel do |channel|
      if request_pty
        channel.request_pty do |_ch, success|
          raise 'failed to allocate a requested PTY for command' unless success
        end
      end

      channel.exec(command) do |_ch, success|
        raise 'failed to execute command in channel' unless success

        # We receive either exit-status or exit-signal. exit-signal contains the
        # name of the signal which the process received. exit-status contains
        # the exit status as uint32.
        channel.on_request('exit-status') do |_ch, data|
          on_complete.call(channel[:server], exit_code: data.read_long, exit_signal: nil)
        end
        channel.on_request('exit-signal') do |_ch, data|
          on_complete.call(channel[:server], exit_code: false, exit_signal: data.read_string)
        end

        channel.on_data do |ch2, data|
          yield ch2, :stdout, data
        end

        channel.on_extended_data do |ch2, type, data|
          yield ch2, :stderr, data if type == 1
        end

        channel.send_data(input) unless input.nil?
        # Always send EOF to prevent things from getting stuck unintentionally.
        channel.eof!
      end
    end
  end

  # Extract lines (separated by \n) from a buffer, in place, and yield the lines
  # to the passed block one by one (including the trailing newline).
  #
  # If a line exceeds the max_line_length, it is yielded even without newline.
  def extract_lines!(buffer)
    # note that this modifies buffer in-place for efficiency
    newline_pos = buffer.index("\n")
    until newline_pos.nil?
      line = buffer.slice!(0..newline_pos)
      yield line
      newline_pos = buffer.index("\n")
    end
    # maximum line length as anti-DoS measure
    # rubocop:disable Style/GuardClause
    if buffer.length >= new_resource.max_line_length
      yield buffer.dup
      buffer.clear
    end
    # rubocop:enable Style/GuardClause
  end

  # Wrapper around ssh_exec which implements line buffering.
  #
  # Like exec_io, this yields the output to the passed block with three
  # arguments: the channel, the stream (:stdout or :stderr) and the line. Lines
  # are emitted including the trailing newline, if it exists.
  #
  # Once the command completes, any unfinished lines are yielded to the block
  # (and those may not have a trailing newline).
  #
  # All arguments and return values behave the same as for exec_io.
  def line_buffered_exec(session, command, on_complete, options)
    # general idea: append data received via SSH to the respective buffers, and
    # flush the buffers to the passed block whenever a newline is encountered
    server_state = {}
    session.servers.each do |srv|
      server_state[srv] = {
        buffers: {
          stdout: '',
          stderr: '',
        },
        channel: nil,
      }
    end

    nested_on_complete = lambda do |server, result|
      state = server_state[server]
      channel = state.fetch(:channel)
      state.fetch(:buffers).each_pair do |stream, remainder|
        next if remainder.empty?
        yield channel, stream, remainder
      end
      on_complete.call(server, result)
    end

    # FIXME: intelligently deal with ANSI escape codes like colour changes.
    exec_io(session, command, nested_on_complete, options) do |event_channel, stream, data|
      this_state = server_state[event_channel[:server]]
      this_state[:channel] = event_channel
      buffers = this_state[:buffers]
      next unless buffers.key?(stream)
      buffer = buffers[stream]
      buffer << data
      extract_lines!(buffer) do |line|
        yield this_state[:channel], stream, line
      end
    end
  end

  # Boilerplate wrapper for executing a command on all servers in a session and
  # collecting the results.
  #
  # Creates a hash mapping the servers to freshly created instances of
  # result_item_class. The hash is then passed to the block. After the block
  # returns, the session is looped until all servers have completed. The
  # connection falied flag from the servers is transferred to the result items
  # and the hash of result items is returned.
  def loop_wrapper(session, result_item_class)
    servers = session.servers
    result_items = servers.map do |srv|
      srv[:connection_failed] = nil
      [srv, result_item_class.new]
    end.to_h

    yield result_items

    session.master.loop do
      servers.any? do |srv|
        !result_items[srv].completed? && srv[:connection_failed].nil?
      end
    end

    servers.each do |srv|
      unless srv[:connection_failed].nil?
        result_items[srv].connection_failed = true
      end
      srv[:connection_failed] = nil
    end

    result_items
  end

  # Execute a command on all hosts and stream the output to standard output,
  # prefixed with the respective server name.
  #
  # Uses line_buffered_exec internally, to which all additional keyword
  # arguments are passed.
  #
  # If sensitive_output is true, only the number of lines emitted by the command
  # is printed (for each host) after it has completed.
  #
  # If sensitive_command is true, the command name is not printed when the exit
  # status is printed after command completion.
  #
  # This waits until all hosts in the session have completed or failed to
  # connect.
  #
  # Return a hash which maps the server objects to the result items for the
  # server.
  def ssh_exec_streamed(session, command, sensitive_command: false, sensitive_output: false, **options)
    lines_by_host = {}
    final_items = loop_wrapper(session, RemoteExec::ResultItem) do |result_items|
      previous_host = nil

      on_complete = lambda do |server, result|
        result_item = result_items[server]
        result_item.exit_code = result[:exit_code]
        result_item.exit_signal = result[:exit_signal]
        # make sure to always have an empty line in front of this output
        puts if previous_host.nil?
        previous_host = server
        puts formatter.streamed_exit_status(server.host, command, sensitive_command, result_item)
      end

      line_buffered_exec(session, command, on_complete, options) do |channel, _stream, line|
        line.slice!(line.length - 1) if line.end_with?("\n")
        this_host = channel[:server]
        lines_by_host[this_host] ||= 0
        lines_by_host[this_host] += 1
        unless sensitive_output
          # print an empty line before the first line for alignment (but only
          # if we actually receive output) and between different hosts for
          # readability
          puts if previous_host != this_host
          previous_host = this_host
          # Add the CLEAR to clear any color codes the remote end may have
          # sent.
          puts formatter.remote_output_line(this_host.host, line)
        end
      end
    end

    if sensitive_output
      # no output was shown before, insert a blank line for alignment
      puts
      lines_by_host.sort.each do |server, nlines|
        puts formatter.suppressed_remote_lines(server.host, nlines)
      end
      puts '(disable suppression of sensitive output by setting sensitive_output to false or :guards)'
    end

    final_items
  end

  # Append to a buffer and discard old content if it exceeds the maximum
  # buffer size.
  def append_ringbuffer!(buffer, data)
    buffer += data
    return unless buffer.length > new_resource.max_buffer_size
    to_cut = buffer.length - new_resource.max_buffer_size
    buffer.slice!(0..to_cut)
  end

  # Like ssh_exec_streamed, but instead of writing the output to standard
  # output immediately, this collects the output in the stdout and stderr
  # attributes of the result items.
  #
  # This also uses exec_io directly instead of adding line buffering, for
  # performance.
  def ssh_exec(session, command, options)
    loop_wrapper(session, RemoteExec::ResultItemWithIO) do |result_items|
      on_complete = lambda do |server, result|
        result_items[server].exit_code = result[:exit_code]
        result_items[server].exit_signal = result[:exit_signal]
      end

      exec_io(session, command, on_complete, options) do |channel, stream, data|
        srv = channel[:server]
        append_ringbuffer!(result_items[srv].streams[stream], data)
      end
    end
  end
end
