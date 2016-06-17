#! /usr/bin/env ruby
#
# check-s3-objects
#
# DESCRIPTION:
#   This plugin checks if the number of objects in a given s3 bucket + folder
#
# OUTPUT:
#   plain-text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: aws-sdk
#   gem: sensu-plugin
#
# USAGE:
#   ./check-s3-objects.rb --bucket-name mybucket --aws-region eu-west-1 --use-iam --key-name "path/to/myfile.txt"
#
# NOTES:
#
# LICENSE:
#   Copyright (c) 2015, Olivier Bazoud, olivier.bazoud@gmail.com
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'sensu-plugin/check/cli'
require 'aws-sdk'

class CheckS3Bucket < Sensu::Plugin::Check::CLI
  option :aws_access_key_id,
         description: 'AWS Access Key',
         short: '-a AWS_ACCESS_KEY',
         long: '--access-key AWS_ACCESS_KEY'

  option :aws_secret_access_key,
         description: 'AWS Secret Access Key',
         short: '-s AWS_SECRET_ACCESS_KEY',
         long: '--secret-access-key AWS_SECRET_ACCESS_KEY'

  option :region,
         description: 'AWS Region',
         short: '-r REGION',
         long: '--region REGION',
         default: 'us-east-1'

  option :bucket,
         description: 'The name of the S3 bucket',
         short: '-b BUCKET',
         long: '--bucket',
         required: true

  option :prefix,
         description: 'The prefix (e.g. nested folders)',
         short: '-p PREFIX',
         long: '--prefix',
         default: ''

  option :warning,
         description: 'Warn if count is greater than or equal to provided value',
         short: '-w COUNT',
         proc: proc(&:to_i),
         long: '--warning COUNT',
         required: true

  option :critical,
         description: 'Critical if count greater than or equal to provided value',
         short: '-c COUNT',
         proc: proc(&:to_i),
         long: '--critical COUNT',
         required: true

  def run
    object_count = begin
      objects.size
    rescue Exception => e
      unknown(e.message)
    end

    if object_count >= config[:critical]
      critical message_for_count(object_count)
    elsif object_count >= config[:warning]
      warning message_for_count(object_count)
    else
      ok message_for_count(object_count)
    end
  end

  def message_for_count(x)
    "#{config[:bucket]}#{config[:prefix]} - #{x} objects"
  end

  def objects
    @objects ||= client.list_objects(bucket: config[:bucket], prefix: config[:prefix]) \
                       .contents
                       .delete_if { |o| o.key == config[:prefix] }
  end

  def client
    @client ||= Aws::S3::Client.new({ region: config[:region] }.merge(credentials))
  end

  def credentials
    return {} unless config[:aws_access_key_id] && config[:aws_secret_access_key]
    { credentials: Aws::Credentials.new(config[:aws_access_key_id], config[:aws_secret_access_key]) }
  end
end
