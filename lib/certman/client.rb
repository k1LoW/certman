module Certman
  class Client
    include Certman::Resource::STS
    include Certman::Resource::S3
    include Certman::Resource::SES
    include Certman::Resource::Route53
    include Certman::Resource::ACM

    def initialize(domain)
      @do_rollback = false
      @domain = domain
      @cert_arn = nil
      @savepoint = []
    end

    def request(remain_resources = false)
      check_resource

      enforce_region_to_us_east_1 do
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

      enforce_region_to_us_east_1 do
        step('[SES] Check Domain Identity Status *verified*', nil) do
          check_domain_identity_verified
        end
      end

      step('[Route53] Create MX Record Set', :route53_mx) do
        create_mx_rset
      end

      enforce_region_to_us_east_1 do
        step('[SES] Create Receipt Rule Set', :ses_rule_set) do
          create_rule_set
        end

        step('[SES] Create Receipt Rule', :ses_rule) do
          create_rule
        end

        step('[SES] Replace Active Receipt Rule Set', :ses_replace_active_rule_set) do
          replace_active_rule_set
        end
      end

      step('[ACM] Request Certificate', :acm_certificate) do
        request_certificate
      end

      enforce_region_to_us_east_1 do
        step('[S3] Check approval mail (will take about 30 min)', nil) do
          check_approval_mail
        end
      end

      cleanup_resources if !remain_resources || @do_rollback

      @cert_arn
    end

    def delete
      s = spinner('[ACM] Delete Certificate')
      delete_certificate
      s.success
    end

    def check_resource
      s = spinner('[ACM] Check Certificate')
      check_certificate
      s.success

      s = spinner('[Route53] Check Hosted Zone')
      check_hosted_zone
      s.success

      s = spinner('[Route53] Check TXT Record')
      check_txt_rset
      s.success

      s = spinner('[Route53] Check MX Record')
      check_mx_rset
      s.success

      true
    end

    def rollback
      @do_rollback = true
    end

    private

    def enforce_region_to_us_east_1
      region = Aws.config[:region]
      unless ['us-east-1', 'us-west-2', 'eu-west-1'].include?(Aws.config[:region])
        Aws.config[:region] = 'us-east-1'
      end
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
      @savepoint.reverse.each do |state|
        case state
        when :s3_bucket
          enforce_region_to_us_east_1 do
            s = spinner('[S3] Delete Bucket')
            delete_bucket
            s.success
          end
        when :ses_domain_identity
          enforce_region_to_us_east_1 do
            s = spinner('[SES] Delete Verified Domain Identiry')
            delete_domain_identity
            s.success
          end
        when :route53_txt
          s = spinner('[Route53] Delete TXT Record Set')
          delete_txt_rset
          s.success
        when :route53_mx
          s = spinner('[Route53] Delete MX Record Set')
          delete_mx_rset
          s.success
        when :ses_rule_set
          enforce_region_to_us_east_1 do
            s = spinner('[SES] Delete Receipt Rule Set')
            delete_rule_set
            s.success
          end
        when :ses_rule
          enforce_region_to_us_east_1 do
            s = spinner('[SES] Delete Receipt Rule')
            delete_rule
            s.success
          end
        when :ses_replace_active_rule_set
          enforce_region_to_us_east_1 do
            s = spinner('[SES] Revert Active Receipt Rule Set')
            revert_active_rue_set
            s.success
          end
        end
      end
    end

    def bucket_name
      @bucket_name ||= if "#{@domain}-generated-by-certman-for-ses-inbound-".length < 63
                         "#{@domain}-generated-by-certman-for-ses-inbound-"
                       elsif "#{@domain}-certman-".length < 63
                         "#{@domain}-certman-"
                       else
                         "#{Digest::SHA1.hexdigest(@domain)}-certman-"
                       end
    end

    def rule_name
      @rule_name ||= if "S3RuleGeneratedByCertman_#{@domain}".length < 64
                       "S3RuleGeneratedByCertman_#{@domain}"
                     elsif "RuleCertman_#{@domain}".length < 64
                       "RuleCertman_#{@domain}"
                     else
                       "RuleCertman_#{Digest::SHA1.hexdigest(@domain)}"
                     end
    end

    def rule_set_name
      @rule_set_name ||= if "RuleSetGeneratedByCertman_#{@domain}".length < 64
                           "RuleSetGeneratedByCertman_#{@domain}"
                         elsif "RuleSetCertman_#{@domain}".length < 64
                           "RuleSetCertman_#{@domain}"
                         else
                           "RuleSetCertman_#{Digest::SHA1.hexdigest(@domain)}"
                         end
    end

    def spinner(message)
      Certman::Log.new(message)
    end
  end
end
