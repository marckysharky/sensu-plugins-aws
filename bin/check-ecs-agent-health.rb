#! /usr/bin/env ruby
#
# check-ecs-agent-health
#
# DESCRIPTION:
#   This plugin uses the AWS ECS API to check the status
#   of the ECS agents running in a given ECS cluster.
#
#   CRIT:
#   WARN:
#   OK:
#
# OUTPUT:
#   plain-text
#
# PLATFORMS:
#   Linux, Windows, Mac
#
# DEPENDENCIES:
#   gem: aws-sdk
#   gem: sensu-plugin
#
# USAGE:
#  ./check-ecs-agent-health.rb -r {us-east-1|eu-west-1} -c default
#
# NOTES:
#
# LICENSE:
#   Marc Watts <marcky.sharky@gmail.com>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
require 'rubygems'
require 'bundler/setup'

require 'sensu-plugin/check/cli'
require 'sensu-plugins-aws'
require 'aws-sdk'

class CheckEcsAgentHealth < Sensu::Plugin::Check::CLI
  include Common

  option :aws_region,
         short: '-r AWS_REGION',
         long: '--aws-region AWS_REGION',
         description: 'The AWS region.',
         default: 'us-east-1'

  option :cluster,
         short: '-c NAME',
         long: '--cluster NAME',
         description: 'The cluster(s) to check.',
         proc: Proc.new { |v| v.to_s.strip.split(',') }

  def run
    unknown "cluster(s) required" if config[:cluster].nil? || config[:cluster].empty?

    clusters  = cluster_statuses_for(Array(config[:cluster]))
    unhealthy = unhealthy_clusters_from(clusters)

    if unhealthy.empty?
      ok(healthy_message_for(clusters))
    else
      critical(critical_message_for(unhealthy))
    end
  rescue => e
    unknown "An error occurred processing AWS ECS API: #{e.message}: #{e.backtrace.join("\n")}"
  end

  private

  def client
    @client ||= Aws::ECS::Client.new(region: config[:aws_region])
  end

  def arns_for(cluster_name, token: nil)
    response = client.list_container_instances(cluster: cluster_name,
                                               max_results: 100,
                                               next_token: token)

    instances = response.container_instance_arns
    instances.push(*list_cluster_instances(cluster_name, token: response.next_token)) if response.next_token
    instances
  end

  def statuses_for(cluster_name, instance_arns)
    resp = client.describe_container_instances(cluster: cluster_name,
                                               container_instances: instance_arns)

    resp.container_instances.each_with_object({}) do |instance, hsh|
      hsh[instance.ec2_instance_id] = instance.agent_connected
    end
  end

  def agent_statuses_for(cluster_name)
    arns = arns_for(cluster_name)
    statuses_for(cluster_name, arns)
  end

  def healthy_message_for(clusters)
    clusters.keys.join(', ')
  end

  def critical_message_for(unhealthy)
    message = unhealthy.keys.join(', ')
    unhealthy.each_with_object(message) do |(name, instances), str|
      str << "\n#{name}: #{instances.keys.join(', ')}"
    end
  end

  def unhealthy_clusters_from(clusters)
    clusters.each_with_object({}) do |(name, instances), hsh|
      unhealthy = instances.select { |_, status| status == false }
      hsh[name] = unhealthy unless unhealthy.empty?
    end
  end

  def cluster_statuses_for(clusters)
    clusters.each_with_object({}) do |cluster_name, hsh|
      hsh[cluster_name] = agent_statuses_for(cluster_name)
    end
  end
end
