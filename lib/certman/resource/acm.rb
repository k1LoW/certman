module Certman
  module Resource
    module ACM
      def request_certificate
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
        @cert_arn = res.certificate_arn
      end

      def acm
        @acm ||= Aws::ACM::Client.new
      end
    end
  end
end
