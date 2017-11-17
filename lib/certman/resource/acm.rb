module Certman
  module Resource
    module ACM
      def request_certificate
        res = acm.request_certificate(
          domain_name: @domain,
          subject_alternative_names: @subject_alternative_names,
          domain_validation_options: [
            {
              domain_name: @domain,
              validation_domain: validation_domain
            }
          ]
        )
        @cert_arn = res.certificate_arn
      end

      def resend_validation_email
        acm.resend_validation_email(
          certificate_arn: @cert_arn,
          domain: @domain,
          validation_domain: validation_domain
        )
      end

      def delete_certificate
        current_cert = acm.list_certificates.certificate_summary_list.find do |cert|
          cert.domain_name == @domain
        end
        raise 'Certificate does not exist' unless current_cert
        acm.delete_certificate(certificate_arn: current_cert.certificate_arn)
      end

      def certificate_exist?
        current_cert = acm.list_certificates.certificate_summary_list.find do |cert|
          cert.domain_name == @domain
        end
        @cert_arn = current_cert&.certificate_arn
      end

      def acm
        @acm ||= Aws::ACM::Client.new
      end
    end
  end
end
