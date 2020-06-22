# -*- mode: ruby -*-
# vi: set ft=ruby :

require 'set'
require 'yaml'
require 'json'

$vagrant_box = ENV['VAGRANT_BOX'] || "bento/centos-7"

# Short-circuting the 'ansible.limit' variable via Vagrant args
arg0 = ARGV[0]
arg1 = ARGV[1] || ""
up_provisioning = (arg0 == "up" && arg1 != "--no-provision") || arg0 == "provision"
host_provisioning = (arg0 == "provision" && arg1 != "")
if host_provisioning
  $ansible_limit = arg1
else
  $ansible_limit = ENV['ANSIBLE_LIMIT'] || 'all'
end

$cp_playbook_dir = "cp-ansible"  # Relative to the Vagrantfile
$cp_security_mode = ENV['CP_SECURITY_MODE'] || 'plaintext'

$profile = ENV['CP_PROFILE'] || 'kafka-1'
$kafka_retention_hours = (ENV['CP_KAFKA_LOG_RETENION_HOURS'] || '48').to_i

def validate_machine_groups(machines)
  zks = machines.select { |_, cfg| cfg['groups'].include? 'zookeeper' }
  if zks.empty?
    raise ValidationError, ['Must have at least one machine in group "zookeeper"']
  end

  brokers = machines.select { |_, cfg| cfg['groups'].include? 'broker' }
  if brokers.empty?
    raise ValidationError, ['Must have at least one machine in group "broker"']
  end
end

def ansible_provision(v, ansible_limit, group_vars, host_vars)
  v.vm.provision "ansible" do |ansible|
    ansible.compatibility_mode = '2.0'
    ansible.playbook = File.join("#{$cp_playbook_dir}", "#{$cp_security_mode}", "all.yml")
    ansible.become = true
    ansible.verbose = "vv"
    ansible.limit = ansible_limit
    ansible.groups = group_vars
    ansible.host_vars = host_vars
  end
end

def set_broker_id(name, machine_conf, broker_id)
  # If broker already has variables
  if machine_conf.key?("vars") && machine_conf["vars"].key?("kafka")
    begin # try to parse the Python-dict formatted broker vars as JSON
      existing_kafka_conf = JSON.parse(machine_conf["vars"]["kafka"])
      # attempt to access existing broker id
      broker_id = existing_kafka_conf["broker"]["id"]
    rescue
      puts "==> #{name} does not have a 'broker.id' value. Setting it to #{broker_id}."
      machine_conf["vars"].merge({"kafka" => "{\"broker\": {\"id\": #{broker_id}}}"})
    end
  else # host vars don't exist, so set them
    puts "==> #{name} does not have a 'broker.id' value. Setting it to #{broker_id}."
    machine_conf["vars"] = {"kafka" => "{\"broker\": {\"id\": #{broker_id}}}"}
  end
end

puts("==> Loading CP_PROFILE='#{$profile}'")
machines = YAML.load_file(File.join(File.dirname(__FILE__), 'profiles', "#{$profile}.yml"))
validate_machine_groups(machines)

Vagrant.configure("2") do |config|

  if Vagrant.has_plugin?("vagrant-hostmanager")
    config.hostmanager.enabled = true
    config.hostmanager.manage_host = true
    config.hostmanager.ignore_private_ip = false
    config.hostmanager.include_offline = true
  end

  # More info on http://fgrehm.viewdocs.io/vagrant-cachier/usage
  if Vagrant.has_plugin?("vagrant-cachier")
    config.cache.scope = :machine
  end

  if Vagrant.has_plugin?("vagrant-vbguest")
    config.vbguest.auto_update = true
  end

  config.vm.box = $vagrant_box
  config.vm.box_check_update = false
  config.vm.synced_folder '.', '/vagrant', disabled: true
  config.ssh.insert_key = false

  ############ Gathering Machine Variables ############
  broker_index = 1

  groups = group_up(machines)
  brokers = groups["broker"]
  # Services won't start if there are less brokers than their
  # configured topic replication factors
  replication_factor = [3, brokers.length].min

  group_vars = {
    "all:vars" => {"security_mode" => $cp_security_mode},
    "broker:vars" => {
      "kafka_broker_config" => "{
        \"log.retention.hours\": #{$kafka_retention_hours},
        \"offsets.topic.replication.factor\": #{replication_factor},
        \"transaction.state.log.replication.factor\": #{replication_factor},
        \"confluent.metrics.reporter.topic.replicas\": #{replication_factor}
      }".gsub(/[[:space:]]/,'')
    },
    "connect-distributed:vars" => {
      "kafka_connect_config" => "{
        \"config.storage.replication.factor\": #{replication_factor},
        \"offset.storage.replication.factor\": #{replication_factor},
        \"status.storage.replication.factor\": #{replication_factor}
      }".gsub(/[[:space:]]/,'')
    },
    "control-center:vars" => {
      "control_center_config" => "{
        \"confluent.controlcenter.command.topic.replication\": #{replication_factor},
        \"confluent.controlcenter.internal.topics.replication\": #{replication_factor},
        \"confluent.metrics.topic.replication\": #{replication_factor},
        \"confluent.monitoring.interceptor.topic.replication\": #{replication_factor},
      }".gsub(/[[:space:]]/,'')
    }
  }
  groups = groups.merge(group_vars)

  ############ Provisioning loop ############
  machines.each_with_index do |(name, machine_conf), index|

    config.vm.define name.to_sym do |v|
      v.vm.network "private_network", ip: "192.168.100.#{101+index}"
      v.vm.hostname = "#{name}.cp.vagrant"

      if machine_conf.key?("ports")
        machine_conf['ports'].each do |guest_port, host_port|
          if host_port.nil?
            host_port = guest_port
          end
          v.vm.network "forwarded_port", guest: guest_port, host: host_port
        end
      end

      v.vm.provider "virtualbox" do |vb|
        vb.name = v.vm.hostname
        vb.memory = machine_conf['memory'] || 1536 # Give overhead for 1G default heaps
        vb.cpus = machine_conf['cpus'] || 1
        vb.customize ["modifyvm", :id, "--ioapic", "on"]
        # NAT proxy is flakey (times out frequently)
        vb.customize ['modifyvm', :id, '--natdnsproxy1', 'off']
        # Host DNS resolution required to support host proxies and faster global DNS resolution
        vb.customize ['modifyvm', :id, '--natdnshostresolver1', 'on']
        # Assign unique mac address
        vb.customize ['modifyvm', :id, '--macaddress1', 'auto']
        # guest should sync time if more than 10s off host
        vb.customize [ "guestproperty", "set", :id, "/VirtualBox/GuestAdd/VBoxService/--timesync-set-threshold", 1000 ]
      end

      # TODO: Add other providers

      v.vm.provision :shell, inline: "sed -i'' '/^127.0.0.1\\t#{v.vm.hostname}\\t#{name}$/d' /etc/hosts"

      if (up_provisioning || host_provisioning)
        # Allow Vagrant to set incremental broker id
        if machine_conf.key?("groups") && machine_conf["groups"].include?("broker")
          set_broker_id(name, machine_conf, broker_index)
          broker_index += 1
        end
      end

      if (up_provisioning && index == machines.length - 1) || (host_provisioning && name == arg1)
        if (up_provisioning || host_provisioning)
          puts "==> Provisioning with ANSIBLE_LIMIT='#{$ansible_limit}'"
        end

        host_vars = host_vars(machines)

        if $ansible_limit != 'all'
          ansible_provision(v, $ansible_limit, groups, host_vars)
        else
          # Provision Certificate Authority
          if groups.key?("ssl_CA")
            ansible_provision(v, 'ssl_CA', groups, host_vars)
          end

          # Ensure Zookeepers are provisioned before other services
          ansible_provision(v, 'zookeeper', groups, host_vars)
          # Ensure Brokers are provisioned before other services
          ansible_provision(v, 'broker', groups, host_vars)

          # Provision non-zookeepers and non-brokers
          # Control Center also depends on other services
          if (groups.key?("tools") ||
              groups.key?("connect-distributed") ||
              groups.key?("schema-registry") ||
              groups.key?("kafka-rest") ||
              groups.key?("ksql"))
            ansible_provision(v, 'all:!zookeeper:!broker:!control-center', groups, host_vars)
          end

          # Ensure all services are up before control center
          if groups.key?("control-center")
            ansible_provision(v, 'control-center', groups, host_vars)
          end

        end
      end # If last machine

      # Install Gremlin
      if File.directory?(File.expand_path("./gremlin"))
        v.vm.synced_folder './gremlin/', '/gremlin'
      end
      v.vm.provision :shell, :path => "install-gremlin.sh", :args => "#{name}", env: {"GREMLIN_TEAM_ID" => ENV['GREMLIN_TEAM_ID'], "GREMLIN_TEAM_SECRET" => ENV['GREMLIN_TEAM_SECRET']}
    end # machine configuration
  end # for each machine
end

# Helper method to define machine groupings
def group_up (machines)
  groups = Hash.new
  machines.each do |name, config|
    config['groups'].each do |group|
      if !groups.has_key?(group)
        groups[group] = Set.new
      end
      groups[group].add(name)
    end
  end

  groups.each do |k, v|
    groups[k] = v.to_a
  end

  all_groups = Array.new
  groups.each do |k, v|
     all_groups.push(k)
  end
  groups["all_groups:children"] = all_groups

  return groups
end

# Helper method to extract host vars
def host_vars(machines)
  hosts = Hash.new
  machines.each do |name, config|
    if config.has_key?('vars')
      hosts[name] = config['vars']
    end
  end

  return hosts
end
