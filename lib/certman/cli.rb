module Certman
  class CLI < Thor
    desc 'request [DOMAIN]', 'Request ACM Certificate with only AWS managed services'
    option :remain_resources, type: :boolean
    def request(domain)
      pastel = Pastel.new
      prompt = TTY::Prompt.new
      return unless prompt.yes?(pastel.red("NOTICE! Your selected region is *#{Aws.config[:region]}*. \
Certman create certificate on *#{Aws.config[:region]}*. OK?"))
      client = Certman::Client.new(domain)
      return unless prompt.yes?(pastel.red("NOTICE! Certman use *#{client.region_by_hash}* S3/SES. OK?"))
      return unless prompt.yes?(pastel.red('NOTICE! When requesting, Certman apend Receipt Rule to current Active Receipt Rule Set. OK?'))
      Signal.trap(:INT) do
        puts ''
        puts pastel.red('Rollback start.')
        client.rollback
      end
      cert_arn = client.request(options[:remain_resources])
      puts 'Done.'
      puts ''
      puts "certificate_arn: #{pastel.cyan(cert_arn)}"
      puts ''
    end

    desc 'delete [DOMAIN]', 'Delete ACM Certificate'
    def delete(domain)
      Certman::Client.new(domain).delete
      puts 'Done.'
      puts ''
    end
  end
end
