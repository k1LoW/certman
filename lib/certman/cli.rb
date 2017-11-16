module Certman
  class CLI < Thor
    desc 'request [DOMAIN]', 'Request ACM Certificate with only AWS managed services'
    option :remain_resources, type: :boolean, default: false
    option :hosted_zone, type: :string, banner: '<Route53 HostedZone>'
    option :non_interactive, type: :boolean, default: false
    option :subject_alternative_names, type: :array, banner: 'alt_domain_1 alt_domain_2...'
    def request(domain)
      prompt = TTY::Prompt.new
      pastel = Pastel.new
      client = Certman::Client.new(domain, options)
      prompt_or_notify(client, prompt, pastel)
      rollback_on_interrupt(client, pastel)
      cert_arn = client.request

      puts 'Done.'
      puts ''
      puts "certificate_arn: #{pastel.cyan(cert_arn)}"
      puts ''
    end

    desc 'restore-resources [DOMAIN]', 'Restore resources to receive approval mail'
    option :hosted_zone, type: :string, banner: '<Route53 HostedZone>'
    option :non_interactive, type: :boolean, default: false
    def restore_resources(domain)
      prompt = TTY::Prompt.new
      pastel = Pastel.new
      client = Certman::Client.new(domain, options)
      prompt_or_notify(client, prompt, pastel)
      rollback_on_interrupt(client, pastel)
      client.restore_resources

      puts 'Done.'
      puts ''
    end

    desc 'delete [DOMAIN]', 'Delete ACM Certificate'
    def delete(domain)
      Certman::Client.new(domain, options).delete

      puts 'Done.'
      puts ''
    end

    private

    def prompt_or_notify(client, prompt, pastel)
      notices = [
        "NOTICE! Your selected region is *#{Aws.config[:region]}*. " \
          "Certman will create a certificate on *#{Aws.config[:region]}*.",
        "NOTICE! Certman has chosen *#{client.region_by_hash}* for S3/SES resources.",
        'NOTICE! When requesting, Certman appends a Receipt Rule to the current Active Receipt Rule Set.'
      ]

      notices.each do |message|
        if options[:non_interactive]
          puts pastel.red(message)
        else
          exit unless prompt.yes?(pastel.red(message << ' OK?'))
        end
      end
    end

    def rollback_on_interrupt(client, pastel)
      Signal.trap(:INT) do
        puts ''
        puts pastel.red('Rollback start.')
        client.rollback
      end
    end
  end
end
