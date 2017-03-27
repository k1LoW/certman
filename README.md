# Certman

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
NOTICE! Certman support *us-east-1* only, now. OK? Yes
NOTICE! When requesting, Certman replace Active Receipt Rule Set. OK? Yes
[✔] [ACM] Check Certificate (successfull)
[✔] [Route53] Check Hosted Zone (successfull)
[✔] [Route53] Check TXT Record (successfull)
[✔] [Route53] Check MX Record (successfull)
[✔] [S3] Create Bucket for SES inbound (successfull)
[✔] [SES] Create Domain Identity (successfull)
[✔] [Route53] Create TXT Record Set to verify Domain Identity (successfull)
[✔] [SES] Check Domain Identity Status *verified* (successfull)
[✔] [Route53] Create MX Record Set (successfull)
[✔] [SES] Create Receipt Rule Set (successfull)
[✔] [SES] Create Receipt Rule (successfull)
[✔] [SES] Replace Active Receipt Rule Set (successfull)
[✔] [ACM] Request Certificate (successfull)
[✔] [S3] Check approval mail (will take about 30 min) (successfull)
[✔] [SES] Revert Active Receipt Rule Set (successfull)
[✔] [SES] Delete Receipt Rule (successfull)
[✔] [SES] Delete Receipt Rule Set (successfull)
[✔] [Route53] Delete MX Record Set (successfull)
[✔] [Route53] Delete TXT Record Set (successfull)
[✔] [SES] Delete Verified Domain Identiry (successfull)
[✔] [S3] Delete Bucket (successfull)
Done.

certificate_arn: arn:aws:acm:us-east-1:0123456789:certificate/123abcd4-5e67-8f90-123a-4567bc89d01

```

#### Remain Resources

If you want to remain resources, use `--remain-resources` option.

(see http://docs.aws.amazon.com/ja_jp/acm/latest/userguide/managed-renewal.html#how-manual-domain-validation-works)

### Delete Certificate

```sh
$ certman delete blog.example.com
[✔] [ACM] Delete Certificate (successfull)
Done.

```

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

