module RemoteExec
  class Formatter
    def highline
      # HighLine is used by chef itself, so it’s not an extra dep \o/
      @highline ||= begin
        require 'highline'
        HighLine.new
      end
    end

    # Wrap a given text into colored brackets, where the color of the brackets
    # is deterministically randomly chosen for the given host.
    #
    # If color output is disabled via chef config, this returns text simply
    # wrapped in (uncolored) square brackets.
    def wrap_colored(color_key, text)
      return "[#{text}]" unless Chef::Config[:color]
      color_cfg = str_to_color(color_key)
      "#{highline.color('[', *color_cfg)}#{text}#{highline.color(']', *color_cfg)}"
    end

    # Prefix to use in front of output lines from remote hosts.
    def host_prefix(host)
      wrap_colored(host, host)
    end

    def remote_output_line(host, line)
      prefix = host_prefix(host)
      # we can only handle clearing the codes if we have HighLine loaded, which
      # is only the case if chef has color output enabled and after we have
      # formatted the prefix
      suffix = HighLine::CLEAR if Chef::Config[:color]
      "#{prefix} #{line}#{suffix}"
    end

    def suppressed_remote_lines(host, nlines)
      wrap_colored(host, "#{host}: #{nlines} line(s) of sensitive output suppressed")
    end

    def streamed_exit_status(host, command, command_sensitive, result_item)
      wrap_colored(host, "#{host}: #{masked_command(command, command_sensitive)} #{result_item.state_to_s}")
    end

    # Mask a command if it is sensitive, return command.inspect otherwise.
    def masked_command(command, sensitive)
      return '(suppressed sensitive command)' if sensitive
      command.inspect
    end

    def compose_exception_message(result_items, command, command_sensitive, command_sensitive_output, allowed_return_codes)
      error_parts = []
      result_items.each_pair do |server, result_item|
        success = result_item.ok?(allowed_return_codes)
        if !success && result_item.connection_failed
          error_parts = [
            "#{server.user}@#{server.host}: failed to connect",
          ]
        elsif !success
          error_parts = [
            "#{server.host}: Expected process to exit with #{allowed_return_codes.inspect}, but it #{result_item.state_to_s}",
          ]
          if command_sensitive_output
            error_parts.push(
              'STDOUT/STDERR suppressed for sensitive resource'
            )
          elsif !result_item.streams.nil?
            local_descriptor = "#{masked_command(command, command_sensitive)} on server #{server.host}"
            error_parts.push(
              "---- Begin output of #{local_descriptor} ----",
              "STDOUT: #{result_item.streams[:stdout]}",
              "STDERR: #{result_item.streams[:stderr]}",
              "---- End output of #{local_descriptor}----"
            )
          end
          error_parts.push('')
        end
      end

      error_parts
    end

    private

    def hash_deterministic(s)
      # we don't use String#hash here because it is not consistent between ruby
      # invocations, and that kind of destroys the recognizability
      Digest::SHA1.digest(s)[0].unpack('C')[0]
    end

    # Return a deterministic random color for a given string
    #
    # The color is chosen from six terminal-safe colors. Returns the color
    # configuration for that color which can be passed to HighLine.
    #
    # FIXME: On a 256-color terminal, we should use more colors.
    def str_to_color(s)
      @str_color_cache ||= {}
      return @str_color_cache[s] if @str_color_cache.key?(s)
      valid_colors = [:red, :green, :blue, :cyan, :magenta, :yellow]
      color = valid_colors[hash_deterministic(s) % valid_colors.length]
      color_cfg = [color, :bold]
      @str_color_cache[s] = color_cfg
      color_cfg
    end
  end
end
