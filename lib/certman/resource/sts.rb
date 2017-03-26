module Certman
  module Resource
    module STS
      def sts
        @sts ||= Aws::STS::Client.new
      end
    end
  end
end
