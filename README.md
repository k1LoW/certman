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
[✔] [Route53] Add TXT Record Set to verify Domain Identity (successfull)
[✔] [SES] Check Domain Identity Status *verified* (successfull)
[✔] [Route53] Add MX Record Set (successfull)
[✔] [SES] Create Receipt Rule (successfull)
[✔] [ACM] Request Certificate (successfull)
[✔] [S3] Check approval mail (will take about 30 min) (successfull)
[✔] [SES] Remove Receipt rule (successfull)
[✔] [Route53] Remove Record Set (successfull)
[✔] [SES] Remove Verified Domain Identiry (successfull)
[✔] [S3] Delete Bucket (successfull)
Done.

certificate_arn: arn:aws:acm:us-east-1:0123456789:certificate/123abcd4-5e67-8f90-123a-4567bc89d01

```

### Delete Certificate

```sh
$ certman delete blog.example.com
[✔] [ACM] Delete Certificate (successfull)
Done.

```

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

