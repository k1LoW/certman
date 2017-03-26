module Certman
  module Resource
    module Route53
      def add_txt_rset
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

      def add_mx_rset
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

      def remove_txt_rset
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
      end

      def remove_mx_rset
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
      end

      def route53
        @route53 ||= Aws::Route53::Client.new
      end
    end
  end
end
