# Certman [![Gem](https://img.shields.io/gem/v/certman.svg)](https://rubygems.org/gems/certman) [![Travis](https://img.shields.io/travis/k1LoW/certman.svg)](https://travis-ci.org/k1LoW/certman)

CLI tool for AWS Certificate Manager.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'certman'
```

And then execute:

```sh
$ bundle
```

Or install it yourself as:

```sh
$ gem install certman
```

## Usage

### Request ACM Certificate with only AWS managed services

```sh
$ certman request blog.example.com
NOTICE! Your selected region is *ap-northeast-1*. Certman create certificate on *ap-northeast-1*. OK? Yes
NOTICE! Certman use *us-east-1* S3/SES. OK? Yes
NOTICE! When requesting, Certman replace Active Receipt Rule Set. OK? Yes
[✔] [ACM] Check Certificate (ap-northeast-1) (successfull)
[✔] [Route53] Check Hosted Zone (ap-northeast-1) (successfull)
[✔] [Route53] Check TXT Record (ap-northeast-1) (successfull)
[✔] [Route53] Check MX Record (ap-northeast-1) (successfull)
[✔] [S3] Create Bucket for SES inbound (us-east-1) (successfull)
[✔] [SES] Create Domain Identity (us-east-1) (successfull)
[✔] [Route53] Create TXT Record Set to verify Domain Identity (ap-northeast-1) (successfull)
[✔] [SES] Check Domain Identity Status *verified* (us-east-1) (successfull)
[✔] [Route53] Create MX Record Set (ap-northeast-1) (successfull)
[✔] [SES] Create Receipt Rule Set (us-east-1) (successfull)
[✔] [SES] Create Receipt Rule (us-east-1) (successfull)
[✔] [SES] Replace Active Receipt Rule Set (us-east-1) (successfull)
[✔] [ACM] Request Certificate (ap-northeast-1) (successfull)
[✔] [S3] Check approval mail (will take about 30 min) (us-east-1) (successfull)
[✔] [SES] Revert Active Receipt Rule Set (us-east-1) (successfull)
[✔] [SES] Delete Receipt Rule (us-east-1) (successfull)
[✔] [SES] Delete Receipt Rule Set (us-east-1) (successfull)
[✔] [Route53] Delete MX Record Set (ap-northeast-1) (successfull)
[✔] [Route53] Delete TXT Record Set (ap-northeast-1) (successfull)
[✔] [SES] Delete Verified Domain Identiry (us-east-1) (successfull)
[✔] [S3] Delete Bucket (us-east-1) (successfull)
Done.

certificate_arn: arn:aws:acm:ap-northeast-1:0123456789:certificate/123abcd4-5e67-8f90-123a-4567bc89d01

```

#### Remain Resources

If you want to remain resources, use `--remain-resources` option.

(see http://docs.aws.amazon.com/ja_jp/acm/latest/userguide/managed-renewal.html#how-manual-domain-validation-works)

### Restore Resources

If you want to restore resources for ACM ( to receive approval mail ), use `certman restore-resources`.

```sh
$ certman restore-resources blog.example.com
```

### Delete Certificate

```sh
$ certman delete blog.example.com
[✔] [ACM] Delete Certificate (successfull)
Done.

```

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

