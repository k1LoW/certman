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

    def request
      check_resource

      step('[S3] Create Bucket for SES inbound', :s3_bucket) do
        create_bucket
      end

      step('[SES] Create Domain Identity', :ses_domain_identity) do
        create_domain_identity
      end

      step('[Route53] Add TXT Record Set to verify Domain Identity', :route53_txt) do
        add_txt_rset
      end

      step('[SES] Check Domain Identity Status *verified*', nil) do
        check_domain_identity_verified
      end

      step('[Route53] Add MX Record Set', :route53_mx) do
        add_mx_rset
      end

      step('[SES] Create Receipt Rule Set', :ses_rule_set) do
        create_rule_set
      end

      step('[SES] Create Receipt Rule', :ses_rule) do
        create_rule
      end

      step('[SES] Replace Active Receipt Rule Set', :ses_replace_active_rule_set) do
        replace_active_rule_set
      end

      step('[ACM] Request Certificate', :acm_certificate) do
        request_certificate
      end

      step('[S3] Check approval mail (will take about 30 min)', nil) do
        check_approval_mail
      end

      cleanup_resources

      @cert_arn
    end

    def delete
      s = spinner('[ACM] Delete Certificate')
      current_cert = acm.list_certificates.certificate_summary_list.find do |cert|
        cert.domain_name == @domain
      end
      raise 'Certificate does not exist' unless current_cert
      acm.delete_certificate(certificate_arn: current_cert.certificate_arn)
      s.success
    end

    def check_resource
      s = spinner('[ACM] Check Certificate')
      current_cert = acm.list_certificates.certificate_summary_list.find do |cert|
        cert.domain_name == @domain
      end
      raise 'Certificate already exist' if current_cert
      s.success

      s = spinner('[Route53] Check Hosted Zone')
      root_domain = PublicSuffix.domain(@domain)
      hosted_zone_id = nil
      hosted_zone = route53.list_hosted_zones.hosted_zones.find do |zone|
        if PublicSuffix.domain(zone.name) == root_domain
          hosted_zone_id = zone.id
          next true
        end
      end
      raise "Hosted Zone #{root_domain} does not exist" unless hosted_zone
      s.success

      s = spinner('[Route53] Check TXT Record')
      res = route53.list_resource_record_sets(
        hosted_zone_id: hosted_zone_id,
        start_record_name: "_amazonses.#{@domain}.",
        start_record_type: 'TXT'
      )
      raise "_amazonses.#{@domain} TXT already exist" unless res.resource_record_sets.empty?
      s.success

      s = spinner('[Route53] Check MX Record')
      res = route53.list_resource_record_sets(
        hosted_zone_id: hosted_zone_id,
        start_record_name: "#{@domain}.",
        start_record_type: 'MX'
      )
      raise "#{@domain} MX already exist" unless res.resource_record_sets.empty?
      s.success

      true
    end

    def rollback
      @do_rollback = true
    end

    private

    def step(message, save)
      return if @do_rollback
      s = spinner(message)
      begin
        yield
        @savepoint.push(save)
        s.success
      rescue
        puts "Error: #{$!}"
        @do_rollback = true
        s.error
      end
    end

    def cleanup_resources
      @savepoint.reverse.each do |state|
        case state
        when :s3_bucket
          s = spinner('[S3] Delete Bucket')
          delete_bucket
          s.success
        when :ses_domain_identity
          s = spinner('[SES] Remove Verified Domain Identiry')
          delete_domain_identity
          s.success
        when :route53_txt
          s = spinner('[Route53] Remove TXT Record Set')
          remove_txt_rset
          s.success
        when :route53_mx
          s = spinner('[Route53] Remove MX Record Set')
          remove_mx_rset
          s.success
        when :ses_rule_set
          s = spinner('[SES] Delete Receipt Rule Set')
          delete_rule_set
          s.success
        when :ses_rule
          s = spinner('[SES] Delete Receipt Rule')
          delete_rule
          s.success
        when :ses_replace_active_rule_set
          s = spinner('[SES] Revert Active Receipt Rule Set')
          revert_active_rue_set
          s.success
        end
      end
    end

    def bucket_name
      @bucket_name ||= "#{@domain}-generated-by-certman-for-ses-inbound-"
    end

    def rule_name
      @rule_name ||= "S3RuleGeneratedByCertman_#{@domain}"
    end

    def rule_set_name
      @rule_set_name ||= "RuleSetGeneratedByCertman_#{@domain}"
    end

    def spinner(message)
      Certman::Log.new(message)
    end
  end
end
