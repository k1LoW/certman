module Certman
  module Resource
    module SES
      REGIONS = %w(us-east-1 us-west-2 eu-west-1)

      def create_domain_identity
        res = ses.verify_domain_identity(domain: @email_domain)
        @token = res.verification_token
      end

      def check_domain_identity_verified
        is_break = false
        100.times do
          res = ses.get_identity_verification_attributes(
            identities: [
              @email_domain
            ]
          )
          if res.verification_attributes[@email_domain].verification_status == 'Success'
            # success
            is_break = true
            break
          end
          break if @do_rollback
          sleep 5
        end
        raise 'Can not check verified' unless is_break
      end

      def delete_domain_identity
        ses.delete_identity(identity: @email_domain)
      end

      def create_rule_set
        ses.create_receipt_rule_set(rule_set_name: rule_set_name)
      end

      def create_rule
        ses.create_receipt_rule(
          rule: {
            recipients: ["admin@#{@email_domain}"],
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

      def replace_active_rule_set
        @current_rule_set_name = nil
        res = ses.describe_active_receipt_rule_set
        @current_rule_set_name = res.metadata.name if res.metadata
        ses.set_active_receipt_rule_set(rule_set_name: rule_set_name)
      end

      def delete_rule_set
        ses.delete_receipt_rule_set(rule_set_name: rule_set_name)
      end

      def delete_rule
        ses.delete_receipt_rule(
          rule_name: rule_name,
          rule_set_name: rule_set_name
        )
      end

      def revert_active_rue_set
        ses.set_active_receipt_rule_set(rule_set_name: @current_rule_set_name)
      end

      def ses
        @ses ||= Aws::SES::Client.new
      end
    end
  end
end
