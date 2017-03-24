module Certman
  class Client
    attr_accessor :do_rollback

    def initialize(domain)
      @do_rollback = false
      @domain = domain
      @savepoint = []
    end

    def request_certificate
      check_resource

      # Get Account ID
      @account_id = sts.get_caller_identity.account

      # Create Bucket for SES inbound
      step('[S3] Create Bucket for SES inbound', :s3_bucket) do
        bucket_policy = <<-"EOF"
{
            "Version": "2008-10-17",
    "Statement": [
        {
            "Sid": "GiveSESPermissionToWriteEmail",
            "Effect": "Allow",
            "Principal": {
                "Service": [
                    "ses.amazonaws.com"
                ]
            },
            "Action": [
                "s3:PutObject"
            ],
            "Resource": "arn:aws:s3:::#{bucket_name}/*",
            "Condition": {
                "StringEquals": {
                    "aws:Referer": "#{@account_id}"
                }
            }
        }
    ]
}
EOF
        s3.create_bucket(
          acl: 'private',
          bucket: bucket_name
        )
        s3.put_bucket_policy(
          bucket: bucket_name,
          policy: bucket_policy,
          use_accelerate_endpoint: false
        )
      end

      # Create Domain Identity
      step('[SES] Create Domain Identity', :ses_domain_identity) do
        res = ses.verify_domain_identity(domain: @domain)
        @token = res.verification_token
      end

      # Add TXT Record Set with Route53
      step('[Route53] Add TXT Record Set to verify Domain Identity', :route53_txt) do
        root_domain = PublicSuffix.domain(@domain)
        @hosted_zone = route53.list_hosted_zones.hosted_zones.find do |zone|
          PublicSuffix.domain(zone.name) == root_domain
        end
        route53.change_resource_record_sets(
          change_batch: {
            changes: [
              {
                action: 'CREATE',
                resource_record_set: {
                  name: "_amazonses.#{@domain}",
                  resource_records: [
                    {
                      value: '"' + @token + '"'
                    }
                  ],
                  ttl: 60,
                  type: 'TXT'
                }
              }
            ],
            comment: 'Generate by certman'
          },
          hosted_zone_id: @hosted_zone.id
        )
      end

      # Checking verify
      step('[SES] Check Domain Identity Status *verified*', nil) do
        is_break = false
        100.times do
          res = ses.get_identity_verification_attributes(
            identities: [
              @domain
            ]
          )
          if res.verification_attributes[@domain].verification_status == 'Success'
            is_break = true
            # success
            break
          end
          break if @do_rollback
          sleep 5
        end
        raise 'no verifiy' unless is_break
      end

      # Add MX Record Set
      step('[Route53] Add MX Record Set', :route53_mx) do
        route53.change_resource_record_sets(
          change_batch: {
            changes: [
              {
                action: 'CREATE',
                resource_record_set: {
                  name: @domain,
                  resource_records: [
                    {
                      value: '10 inbound-smtp.us-east-1.amazonaws.com'
                    }
                  ],
                  ttl: 60,
                  type: 'MX'
                }
              }
            ],
            comment: 'Generate by certman'
          },
          hosted_zone_id: @hosted_zone.id
        )
      end

      # Create Receipt Rule
      step('[SES] Create Receipt Rule Set', :ses_rule_set) do
        ses.create_receipt_rule_set(rule_set_name: rule_set_name)
      end

      step('[SES] Create Receipt Rule', :ses_rule) do
        ses.create_receipt_rule(
          rule: {
            recipients: ["admin@#{@domain}"],
            actions: [
              {
                s3_action: {
                  bucket_name: bucket_name
                }
              }
            ],
            enabled: true,
            name: rule_name,
            scan_enabled: true,
            tls_policy: 'Optional'
          },
          rule_set_name: rule_set_name
        )
      end

      step('[SES] Replace Active Receipt Rule Set', :ses_replace_active_rule_set) do
        @current_rule_set_name = nil
        res = ses.describe_active_receipt_rule_set
        @current_rule_set_name = res.metadata.name if res.metadata
        ses.set_active_receipt_rule_set(rule_set_name: rule_set_name)
      end

      # Request Certificate
      cert_arn = nil
      step('[ACM] Request Certificate', :acm_certificate) do
        res = acm.request_certificate(
          domain_name: @domain,
          subject_alternative_names: [@domain],
          domain_validation_options: [
            {
              domain_name: @domain,
              validation_domain: @domain
            }
          ]
        )
        cert_arn = res.certificate_arn
      end

      # Check Mail and Approve
      step('[S3] Check approval mail (will take about 30 min)', nil) do
        is_break = false
        60.times do
          s3.list_objects(bucket: bucket_name).contents.map do |object|
            res = s3.get_object(bucket: bucket_name, key: object.key)
            res.body.read.match(%r{https://certificates\.amazon\.com/approvals[^\s]+}) do |md|
              cert_uri = md[0]
              handle = open(cert_uri)
              document = Oga.parse_html(handle)
              data = {}
              document.css('form input').each do |input|
                data[input.get('name')] = input.get('value')
              end
              res = Net::HTTP.post_form(URI.parse('https://certificates.amazon.com/approvals'), data)
              if res.body =~ /Success/
              # success
              else
                raise 'Can not approve'
              end
              is_break = true
              break
            end
          end
          break if is_break
          break if @do_rollback
          sleep 30
        end
        raise 'Can not approve' unless is_break
      end

      cleanup_resources

      cert_arn
    end

    def delete_certificate
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

    private

    def step(message, save)
      return if @do_rollback
      s = spinner(message)
      begin
        yield
        @savepoint.push(save)
        s.success
      rescue
        @do_rollback = true
        s.error
      end
    end

    def cleanup_resources
      @savepoint.reverse.each do |state|
        case state
        when :s3_bucket
          # Delete S3 for SES inbound
          s = spinner('[S3] Delete Bucket')
          objects = s3.list_objects(bucket: bucket_name).contents.map do |object|
            { key: object.key }
          end
          unless objects.empty?
            s3.delete_objects(
              bucket: bucket_name,
              delete: {
                objects: objects
              }
            )
          end
          s3.delete_bucket(bucket: bucket_name)
          s.success
        when :ses_domain_identity
          # Remove Verified Domain Identiry
          s = spinner('[SES] Remove Verified Domain Identiry')
          ses.delete_identity(identity: @domain)
          s.success
        when :route53_txt
          # Remove TXT Record Set
          s = spinner('[Route53] Remove TXT Record Set')
          route53.change_resource_record_sets(
            change_batch: {
              changes: [
                {
                  action: 'DELETE',
                  resource_record_set: {
                    name: "_amazonses.#{@domain}",
                    resource_records: [
                      {
                        value: '"' + @token + '"'
                      }
                    ],
                    ttl: 60,
                    type: 'TXT'
                  }
                }
              ],
              comment: 'Generate by certman'
            },
            hosted_zone_id: @hosted_zone.id
          )
          s.success
        when :route53_mx
          # Remove MX Record Set
          s = spinner('[Route53] Remove MX Record Set')
          route53.change_resource_record_sets(
            change_batch: {
              changes: [
                {
                  action: 'DELETE',
                  resource_record_set: {
                    name: @domain,
                    resource_records: [
                      {
                        value: '10 inbound-smtp.us-east-1.amazonaws.com'
                      }
                    ],
                    ttl: 60,
                    type: 'MX'
                  }
                }
              ],
              comment: 'Generate by certman'
            },
            hosted_zone_id: @hosted_zone.id
          )
          s.success
        when :ses_rule_set
          # Remove Receipt Rule Set
          s = spinner('[SES] Remove Receipt Rule Set')
          ses.delete_receipt_rule_set(rule_set_name: @rule_set_name)
          s.success
        when :ses_rule
          # Remove Receipt Rule
          s = spinner('[SES] Remove Receipt Rule')
          ses.delete_receipt_rule(
            rule_name: rule_name,
            rule_set_name: rule_set_name
          )
          s.success
        when :ses_replace_active_rule_set
          # Revert Active Receipt Rule Set
          s = spinner('[SES] Revert Active Receipt Rule Set')
          ses.set_active_receipt_rule_set(rule_set_name: @current_rule_set_name)
          s.success
        end
      end
    end

    def sts
      @sts ||= Aws::STS::Client.new
    end

    def s3
      @s3 ||= Aws::S3::Client.new
    end

    def ses
      @ses ||= Aws::SES::Client.new
    end

    def route53
      @route53 ||= Aws::Route53::Client.new
    end

    def acm
      @acm ||= Aws::ACM::Client.new
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
