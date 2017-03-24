module Certman
  class CLI < Thor
    desc 'request [DOMAIN]', 'Request ACM Certificate with only AWS managed services'
    def request(domain)
      pastel = Pastel.new
      prompt = TTY::Prompt.new
      return unless prompt.yes?(pastel.red('NOTICE! Certman support *us-east-1* only, now. OK?'))
      return unless prompt.yes?(pastel.red('NOTICE! When requesting, Certman replace Active Receipt Rule Set. OK?'))
      client = Certman::Client.new(domain)
      Signal.trap(:INT) do
        puts ''
        puts pastel.red('Rollback start.')
        client.do_rollback = true
      end
      cert_arn = client.request_certificate
      puts 'Done.'
      puts ''
      puts "certificate_arn: #{pastel.cyan(cert_arn)}"
      puts ''
    end

    desc 'delete [DOMAIN]', 'Delete ACM Certificate'
    def delete(domain)
      Certman::Client.new(domain).delete_certificate
      puts 'Done.'
      puts ''
    end
  end
end
