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
NOTICE! Your selected region is *ap-northeast-1*. Certman will create a certificate on *ap-northeast-1*. OK? Yes
NOTICE! Certman has chosen *us-east-1*  for S3/SES resources. OK? Yes
NOTICE! When requesting, Certman appends a Receipt Rule to the current Active Receipt Rule Set. OK? Yes
[✔] [ACM] Check Certificate (us-east-1) (successful)
[✔] [Route53] Check Hosted Zone (us-east-1) (successful)
[✔] [Route53] Check TXT Record (us-east-1) (successful)
[✔] [Route53] Check MX Record (us-east-1) (successful)
[✔] [SES] Check Active Rule Set (us-east-1) (successful)
[✔] [S3] Create Bucket for SES inbound (us-east-1) (successful)
[✔] [SES] Create Domain Identity (us-east-1) (successful)
[✔] [Route53] Create TXT Record Set to verify Domain Identity (us-east-1) (successful)
[✔] [SES] Check Domain Identity Status *verified* (us-east-1) (successful)
[✔] [Route53] Create MX Record Set (us-east-1) (successful)
[✔] [SES] Create and Active Receipt Rule Set (us-east-1) (successful)
[✔] [SES] Create Receipt Rule (us-east-1) (successful)
[✔] [ACM] Request Certificate (us-east-1) (successful)
[✔] [S3] Check approval mail (will take about 30 min) (us-east-1) (successful)
[✔] [SES] Delete Receipt Rule (us-east-1) (successful)
[✔] [SES] Delete Receipt Rule Set (us-east-1) (successful)
[✔] [Route53] Delete MX Record Set (us-east-1) (successful)
[✔] [Route53] Delete TXT Record Set (us-east-1) (successful)
[✔] [SES] Delete Verified Domain Identiry (us-east-1) (successful)
[✔] [S3] Delete Bucket (us-east-1) (successful)
Done.

certificate_arn: arn:aws:acm:ap-northeast-1:0123456789:certificate/123abcd4-5e67-8f90-123a-4567bc89d01
```

OR

```sh
NOTICE! Your selected region is *us-east-1*. Certman will create a certificate on *us-east-1*.
NOTICE! Certman has chosen *us-east-1* for S3/SES resources.
NOTICE! When requesting, Certman appends a Receipt Rule to the current Active Receipt Rule Set.
[✖] [ACM] Check Certificate (us-east-1) (error)

Certificate already exists!

certificate_arn: arn:aws:acm:us-east-1:0123456789:certificate/123abcd4-5e67-8f90-123a-4567bc89d01
```

#### Flags

##### `--remain-resources`
Skips deleting resources after a certificate has been successfully generated. This is necessary if you cannot use automatic validation (i.e., if your site is not accessible to the public internet via HTTPS). See [How Manual Domain Validation Works](http://docs.aws.amazon.com/acm/latest/userguide/how-domain-validation-works.html) for more information.

##### `--non-interactive`
Suppresses prompts from Certman (i.e, if using with a CI system, such as Travis or Jenkins).

##### `--subject-alternative-names=www.test.example.com cert.test.example.com`
Other domain names (separated by spaces) to associate with the requested certificate. Note that only the primary domain name is used for identification purposes and that AWS initially limits each certifcate to 10 SANs.

##### `--hosted-zone=test.example.com`
Specify the name (not the ID) of the Route53 Hosted Zone where the DNS record sets Certman uses will be located. By default, Certman will use the apex domain (i.e. "test.example.com" will have a default hosted-zone of "example.com").

### Restore Resources

If you want to restore resources generated for an ACM certificate (i.e., in order to receive approval mail again, use `certman restore-resources`. This supports the `--non-interactive` and `--hosted-zone` flags from `certman request`.

```sh
$ certman restore-resources blog.example.com
```

### Delete Certificate

```sh
$ certman delete blog.example.com
[✔] [ACM] Delete Certificate (successful)
Done.

```

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

