module Certman
  class Client
    attr_reader :domain

    def initialize(domain)
      @domain = domain
    end

    def request_certificate
      check_resource

      # Get Account ID
      account_id = sts.get_caller_identity.account

      # Create S3 for SES inbound
      s = spinner('[S3] Create Bucket for SES inbound')
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
                    "aws:Referer": "#{account_id}"
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
      s.success

      # Verify New Domain Identity
      s = spinner('[SES] Create Domain Identity')
      res = ses.verify_domain_identity(domain: domain)
      token = res.verification_token
      s.success

      # Add TXT Record Set with Route53
      s = spinner('[Route53] Add TXT Record Set to verify Domain Identity')
      root_domain = PublicSuffix.domain(domain)
      hosted_zone = route53.list_hosted_zones.hosted_zones.find do |zone|
        PublicSuffix.domain(zone.name) == root_domain
      end
      route53.change_resource_record_sets(
        change_batch: {
          changes: [
            {
              action: 'CREATE',
              resource_record_set: {
                name: "_amazonses.#{domain}",
                resource_records: [
                  {
                    value: '"' + token + '"'
                  }
                ],
                ttl: 60,
                type: 'TXT'
              }
            }
          ],
          comment: 'Generate by certman'
        },
        hosted_zone_id: hosted_zone.id
      )
      s.success

      # Checking verify
      s = spinner('[SES] Checking verify')
      is_break = false
      100.times do
        res = ses.get_identity_verification_attributes(
          identities: [
            domain
          ]
        )
        if res.verification_attributes[domain].verification_status == 'Success'
          is_break = true
          s.success
          break
        end
        sleep 5
      end
      s.error unless is_break

      # Add MX Record Set
      s = spinner('[Route53] Add MX Record Set')
      route53.change_resource_record_sets(
        change_batch: {
          changes: [
            {
              action: 'CREATE',
              resource_record_set: {
                name: domain,
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
        hosted_zone_id: hosted_zone.id
      )
      s.success

      # Create Receipt rule
      s = spinner('[SES] Create Receipt Rule')
      rule_name = "S3RuleGeneratedByCertman_#{domain}"
      rule_set_name = "RuleSetGeneratedByCertman_#{domain}"
      ses.create_receipt_rule_set(rule_set_name: rule_set_name)
      ses.create_receipt_rule(
        rule: {
          recipients: ["admin@#{domain}"],
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
      current_rule_set_name = nil
      res = ses.describe_active_receipt_rule_set
      current_rule_set_name = res.metadata.name if res.metadata
      ses.set_active_receipt_rule_set(rule_set_name: rule_set_name)
      s.success

      # Request Certificate
      s = spinner('[ACM] Request Certificate')
      res = acm.request_certificate(
        domain_name: domain,
        subject_alternative_names: [domain],
        domain_validation_options: [
          {
            domain_name: domain,
            validation_domain: domain
          }
        ]
      )
      cert_arn = res.certificate_arn
      s.success

      # Approve E-mail
      s = spinner('[S3] Checking Mail (for 30min)')
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
              s.success
            else
              s.error
            end
            is_break = true
            break
          end
        end
        break if is_break
        sleep 30
      end
      s.error unless is_break

      # Remove Receipt rule
      s = spinner('[SES] Remove Receipt rule')
      ses.set_active_receipt_rule_set(rule_set_name: current_rule_set_name)
      ses.delete_receipt_rule(
        rule_name: rule_name,
        rule_set_name: rule_set_name
      )
      ses.delete_receipt_rule_set(rule_set_name: rule_set_name)
      s.success

      # Remove Record Set
      s = spinner('[Route53] Remove Record Set')
      route53.change_resource_record_sets(
        change_batch: {
          changes: [
            {
              action: 'DELETE',
              resource_record_set: {
                name: "_amazonses.#{domain}",
                resource_records: [
                  {
                    value: '"' + token + '"'
                  }
                ],
                ttl: 60,
                type: 'TXT'
              }
            },
            {
              action: 'DELETE',
              resource_record_set: {
                name: domain,
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
        hosted_zone_id: hosted_zone.id
      )
      s.success

      # Remove Verified Domain Identiry
      s = spinner('[SES] Remove Verified Domain Identiry')
      ses.delete_identity(identity: domain)
      s.success

      # Delete S3 for SES inbound
      s = spinner('[S3] Delete Bucket')
      objects = s3.list_objects(bucket: bucket_name).contents.map do |object|
        { key: object.key }
      end
      s3.delete_objects(
        bucket: bucket_name,
        delete: {
          objects: objects
        }
      )
      s3.delete_bucket(bucket: bucket_name)
      s.success

      cert_arn
    end

    def delete_certificate
      s = spinner('[ACM] Delete Certificate')
      current_cert = acm.list_certificates.certificate_summary_list.find do |cert|
        cert.domain_name == domain
      end
      raise 'Certificate does not exist' unless current_cert
      acm.delete_certificate(certificate_arn: current_cert.certificate_arn)
      s.success
    end

    def check_resource
      s = spinner('[ACM] Check Certificate')
      current_cert = acm.list_certificates.certificate_summary_list.find do |cert|
        cert.domain_name == domain
      end
      raise 'Certificate already exist' if current_cert
      s.success

      s = spinner('[Route53] Check Hosted Zone')
      root_domain = PublicSuffix.domain(domain)
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
        start_record_name: "_amazonses.#{domain}.",
        start_record_type: 'TXT'
      )
      raise "_amazonses.#{domain} TXT already exist" unless res.resource_record_sets.empty?
      s.success

      s = spinner('[Route53] Check MX Record')
      res = route53.list_resource_record_sets(
        hosted_zone_id: hosted_zone_id,
        start_record_name: "#{domain}.",
        start_record_type: 'MX'
      )
      raise "#{domain} MX already exist" unless res.resource_record_sets.empty?
      s.success

      true
    end

    private

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
      @bucket_name ||= "#{domain}-generated-by-certman-for-ses-inbound-"
    end

    def spinner(message)
      Certman::Log.new(message)
    end
  end
end
