module Certman
  class CLI < Thor
    desc 'request [DOMAIN]', 'Request ACM Certificate with only AWS managed services'
    def request(domain)
      pastel = Pastel.new
      cert_arn = Certman::Client.new(domain).request_certificate
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
