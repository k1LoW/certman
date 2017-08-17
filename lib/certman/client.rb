module Certman
  class Client
    include Certman::Resource::STS
    include Certman::Resource::S3
    include Certman::Resource::SES
    include Certman::Resource::Route53
    include Certman::Resource::ACM

    def initialize(domain, options)
      @do_rollback = false
      @cname_exists = false
      @domain = domain
      @cert_arn = nil
      @savepoint = []
      @remain_resources = options[:remain_resources]
      @hosted_zone_domain = options[:hosted_zone]
      @hosted_zone_domain.sub(/\.\z/, '') unless @hosted_zone_domain.nil?
    end

    def request
      check_resource

      enforce_region_by_hash do
        step('[S3] Create Bucket for SES inbound', :s3_bucket) do
          create_bucket
        end
        step('[SES] Create Domain Identity', :ses_domain_identity) do
          create_domain_identity
        end
      end

      step('[Route53] Create TXT Record Set to verify Domain Identity', :route53_txt) do
        create_txt_rset
      end

      enforce_region_by_hash do
        step('[SES] Check Domain Identity Status *verified*', nil) do
          check_domain_identity_verified
        end

        step('[Route53] Create MX Record Set', :route53_mx) do
          create_mx_rset
        end

        unless active_rule_set_exist?
          step('[SES] Create and Active Receipt Rule Set', :ses_rule_set) do
            create_and_active_rule_set
          end
        end

        step('[SES] Create Receipt Rule', :ses_rule) do
          create_rule
        end
      end

      step('[ACM] Request Certificate', :acm_certificate) do
        request_certificate
      end

      enforce_region_by_hash do
        step('[S3] Check approval mail (will take about 30 min)', nil) do
          check_approval_mail
        end
      end

      cleanup_resources if !@remain_resources || @do_rollback

      @cert_arn
    end

    def restore_resources
      check_resource(check_acm: false)

      enforce_region_by_hash do
        step('[S3] Create Bucket for SES inbound', :s3_bucket) do
          create_bucket
        end
        step('[SES] Create Domain Identity', :ses_domain_identity) do
          create_domain_identity
        end
      end

      step('[Route53] Create TXT Record Set to verify Domain Identity', :route53_txt) do
        create_txt_rset
      end

      enforce_region_by_hash do
        step('[SES] Check Domain Identity Status *verified*', nil) do
          check_domain_identity_verified
        end

        step('[Route53] Create MX Record Set', :route53_mx) do
          create_mx_rset
        end

        unless active_rule_set_exist?
          step('[SES] Create and Active Receipt Rule Set', :ses_rule_set) do
            create_and_active_rule_set
          end
        end

        step('[SES] Create Receipt Rule', :ses_rule) do
          create_rule
        end
      end

      cleanup_resources if @do_rollback
    end

    def delete
      s = spinner('[ACM] Delete Certificate')
      delete_certificate
      s.success
    end

    def check_resource(check_acm: true)
      pastel = Pastel.new

      if check_acm
        s = spinner('[ACM] Check Certificate')
        raise 'Certificate already exist' if certificate_exist?
        s.success
      end

      s = spinner('[Route53] Check Hosted Zone')
      raise "Hosted Zone #{hosted_zone_domain} does not exist" unless hosted_zone_exist?
      s.success

      s = spinner('[Route53] Check TXT Record')
      raise "_amazonses.#{email_domain} TXT already exist" if txt_rset_exist?
      s.success

      enforce_region_by_hash do
        s = spinner('[Route53] Check MX Record')
        raise "#{email_domain} MX already exist" if mx_rset_exist?
        if cname_rset_exist?
          puts pastel.cyan("\n#{email_domain} CNAME already exist. Use #{hosted_zone_domain}")
          @cname_exists = true
          check_resource
        end
        s.success

        s = spinner('[SES] Check Active Rule Set')
        if active_rule_set_exist?
          puts pastel.cyan("\nActive Rule Set already exist. Use #{@current_active_rule_set_name}")
        end
        s.success
      end

      true
    end

    def rollback
      @do_rollback = true
    end

    private

    def enforce_region_by_hash
      region = Aws.config[:region]
      Aws.config[:region] = region_by_hash
      yield
      Aws.config[:region] = region
    end

    def step(message, save)
      return if @do_rollback
      s = spinner(message)
      begin
        yield
        @savepoint.push(save)
        s.success
      rescue => e
        pastel = Pastel.new
        puts ''
        puts pastel.red("Error: #{e.message}")
        @do_rollback = true
        s.error
      end
    end

    def cleanup_resources
      pastel = Pastel.new
      @savepoint.reverse.each do |state|
        case state
        when :s3_bucket
          enforce_region_by_hash do
            s = spinner('[S3] Delete Bucket')
            delete_bucket
            s.success
          end
        when :ses_domain_identity
          enforce_region_by_hash do
            s = spinner('[SES] Delete Verified Domain Identiry')
            delete_domain_identity
            s.success
          end
        when :route53_txt
          s = spinner('[Route53] Delete TXT Record Set')
          delete_txt_rset
          s.success
        when :route53_mx
          enforce_region_by_hash do
            s = spinner('[Route53] Delete MX Record Set')
            delete_mx_rset
            s.success
          end
        when :ses_rule_set
          enforce_region_by_hash do
            s = spinner('[SES] Delete Receipt Rule Set')
            if rule_exist?
              puts pastel.cyan("\nReceipt Rule exist. Can not delete Receipt Rule Set.")
              s.error
            else
              delete_rule_set
              s.success
            end
          end
        when :ses_rule
          enforce_region_by_hash do
            s = spinner('[SES] Delete Receipt Rule')
            delete_rule
            s.success
          end
        when :acm_certificate
          if @do_rollback
            s = spinner('[ACM] Delete Certificate')
            delete_certificate
            @cert_arn = nil
            s.success
          end
        end
      end
    end

    def bucket_name
      @bucket_name ||= if "#{email_domain}-certman".length < 63
                         "#{email_domain}-certman"
                       else
                         "#{Digest::SHA1.hexdigest(email_domain)}-certman"
                       end
    end

    def hosted_zone_domain
      return @hosted_zone_domain if @hosted_zone_domain
      root_domain
    end

    def root_domain
      PublicSuffix.domain(@domain)
    end

    def email_domain
      return hosted_zone_domain if @cname_exists
      @domain.sub(/\A(www|\*)\./, '')
    end

    def validation_domain
      return hosted_zone_domain if @cname_exists
      @domain
    end

    def rule_name
      @rule_name ||= if "RuleCertman_#{email_domain}".length < 64
                       "RuleCertman_#{email_domain}"
                     else
                       "RuleCertman_#{Digest::SHA1.hexdigest(email_domain)}"
                     end
    end

    def rule_set_name
      @rule_set_name ||= @current_active_rule_set_name
      @rule_set_name ||= Certman::Resource::SES::RULE_SET_NAME_BY_CERTMAN
    end

    def spinner(message)
      Certman::Log.new(message)
    end
  end
end
