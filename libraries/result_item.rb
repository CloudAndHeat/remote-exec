module RemoteExec
  class ResultItem
    attr_accessor :exit_signal
    attr_accessor :exit_code
    attr_accessor :connection_failed

    def initialize
      @exit_signal = nil
      @exit_code = nil
      @connection_failed = false
    end

    # Format the state of the result item in human-readable form
    def state_to_s
      return 'failed to connect' if @connection_failed
      return "was terminated by SIG#{@exit_signal}" if @exit_code == false
      return "returned exit status #{@exit_code}" unless @exit_code.nil?
      'has not returned yet'
    end

    # This item does not have any output streams. See ResultItemWithIO.
    def streams
      nil
    end

    def completed?
      !@exit_code.nil? || @connection_failed
    end

    def ok?(allowed_exit_codes)
      allowed_exit_codes.include?(@exit_code)
    end
  end

  class ResultItemWithIO < ResultItem
    attr_reader :streams

    def initialize
      @streams = { stdout: '', stderr: '' }
    end
  end
end
