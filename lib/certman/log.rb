module Certman
  class Log
    def initialize(message)
      @pastel = Pastel.new
      @s = TTY::Spinner.new("[:spinner] #{message}", output: $stdout)
      @s.auto_spin
    end

    def success
      @s.success(@pastel.green('(successfull)'))
    end

    def error
      @s.error(@pastel.red('(error)'))
    end
  end
end
