module Certman
  module Resource
    module S3
      def create_bucket
        account_id = sts.get_caller_identity.account
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
      end

      def check_approval_mail
        is_break = false
        30.times do
          sleep 60
          s3.list_objects(bucket: bucket_name).contents.map do |object|
            res = s3.get_object(bucket: bucket_name, key: object.key)
            res.body.read.match(%r{https://[^\s]*certificates\.amazon\.com/approvals[^\s]+}) do |md|
              cert_uri = md[0]
              handle = open(cert_uri)
              document = Oga.parse_html(handle)
              data = {}
              document.css('form input').each do |input|
                data[input.get('name')] = input.get('value')
              end
              post_uri = cert_uri.sub(/\?.*/, '')
              res = Net::HTTP.post_form(URI.parse(post_uri), data)
              raise 'Can not approve' unless res.body =~ /Success/
              # success
              is_break = true
              break
            end
          end
          break if is_break
          break if @do_rollback
          resend_validation_email
        end
        raise 'Can not approve' unless is_break
      end

      def delete_bucket
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
      end

      def s3
        @s3 ||= Aws::S3::Client.new
      end
    end
  end
end
