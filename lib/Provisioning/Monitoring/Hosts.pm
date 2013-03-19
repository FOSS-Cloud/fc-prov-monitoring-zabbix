package Provisioning::Monitoring::Hosts;

# Copyright (C) 2012 FOSS-Group
#                    Germany
#                    http://www.foss-group.de
#                    support@foss-group.de
#
# Authors:
#  Stijn Van Paesschen <stijn_van_paesschen@student.groept.be>
#  
# Licensed under the EUPL, Version 1.1 or – as soon they
# will be approved by the European Commission - subsequent
# versions of the EUPL (the "Licence");
# You may not use this work except in compliance with the
# Licence.
# You may obtain a copy of the Licence at:
#
# http://www.osor.eu/eupl
#
# Unless required by applicable law or agreed to in
# writing, software distributed under the Licence is
# distributed on an "AS IS" basis,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
# express or implied.
# See the Licence for the specific language governing
# permissions and limitations under the Licence.
#

use strict;
use warnings;
use JSON::RPC::Client;

BEGIN {
	require Exporter;
	
	# set the version for version checking
	our $VERSION = 1.00;
	
	# inherit from Exporter to export functions and variables
	our @ISA = qw(Exporter);
	
	# functions and variables which are exported by default
	our @EXPORT = qw(initHosts getHosts getHostID createHost createHostByTemplate deleteHost setStatusHost unlinkTemplatesHost getHostgroupsOfHost addHostToHostgroup removeHostFromHostgroup linkTemplateHost);
	
	# functions and variables which can be optionally exported
	our @EXPORT_OK = qw(existNameHost);
	
	}
			

# Private
        
    my $client = new JSON::RPC::Client;
    my $jsonRPC;
    my $authID;
    my $zabbixApiURL;
    my $defaultInterface = [
			{
				type => 1,
				main => 1,
				useip => 1,
				ip => "127.0.0.1",
				dns => "",
				port => "10050"
			}
		];

# Constructor subroutine
	sub initHosts {
		my ($auth, $apiUrl, $rpcVersion) = @_;
		
		$authID = $auth;
		$zabbixApiURL = $apiUrl;
		$jsonRPC = $rpcVersion;
		
		return 1; 
		
		}
    
# Public 

	###############
	# Zabbix API get hosts
	#

	sub getHosts {
		my ($zabbixOption) = @_;
		
		my $response;
		my $json = {
			jsonrpc => $jsonRPC,
			method => "host.get",
			params => { 
				output => ['hostid', 'host', 'name', 'status' ],
				sortfield => 'name',
				$zabbixOption => 'true',
	
			},
			auth => $authID,
			id => 1
		};
		$response = $client->call($zabbixApiURL, $json);
		
		# Check if response was successful
		if($response->content->{'result'}) {
				return $response->content->{'result'};
				} else {
					logger("error","Get Hosts failed.");
					return 0;
					}		
	}

	###############
	# Zabbix API get hostID
	#

	sub getHostID {
		my ($name) = @_;
		
		my $response;
		my $json = {
			jsonrpc => $jsonRPC,
			method => "host.get",
			params => { 
				output => ['hostid'],
				filter => {
					host => [
						$name
					]
				       }
			},
			auth => $authID,
			id => 1
		};
		$response = $client->call($zabbixApiURL, $json);
		
		# Check if response was successful
		if($response->content->{'result'}) {
				return $response->content->{'result'}[0]->{'hostid'};
				} else {
					logger("error","Get Host id failed.");
					return 0;
					}		
	}



	###############
	# Zabbix API create host
	#

	sub createHost {
		my ($hostName, $hostGroupID) = @_;
		
		if(!existNameHost($hostName)) {
			my $response; 
			my $json = {
				jsonrpc => $jsonRPC,
				method => "host.create",
				params => { 
					host => $hostName,
					interfaces => $defaultInterface,
					groups => [
						{ 
							groupid => $hostGroupID
						}
					]

				},
				auth => $authID,
				id => 1
			};
			$response = $client->call($zabbixApiURL, $json);
			
			# Check if response was successful	
			if($response->content->{'result'}) {
				return $response->content->{'result'};
				} else {
					logger("error","Create Host failed.");
					return 0;
					}
		} else {
				logger("warning","Tried creating a Host that already exists with the same name. Did not create a new Host.");
				return getHostID($hostName);
			}
		
	}
	
	###############
	# Zabbix API create host by template
	#

	sub createHostByTemplate {
		my ($hostName, $hostGroupID, $templateID) = @_;
		
		if(!existNameHost($hostName)) {
			my $response;
			my $interface = [
				{
					type => 1,
					main => 1,
					useip => 1,
					ip => "127.0.0.1",
					dns => "",
					port => "10050"
				}
			]; 
			my $json = {
				jsonrpc => $jsonRPC,
				method => "host.create",
				params => { 
					host => $hostName,
					interfaces => $defaultInterface,
					groups => [
						{ 
							groupid => $hostGroupID
						}
					],
					templates => [
						{
							templateid => $templateID
						}
					]

				},
				auth => $authID,
				id => 1
			};
			$response = $client->call($zabbixApiURL, $json);
			
			# Check if response was successful	
			if($response->content->{'result'}) {
				return $response->content->{'result'};
				} else {
					logger("error","Create Host by template failed.");
					return 0;
					}
		} else {
				logger("warning","Tried creating a Host by template that already exists with the same name. Did not create a new Host.");
				return getHostID($hostName);
			}
		
	}

	###############
	# Zabbix API delete host
	#

	sub deleteHost {
		my ($hostID) = @_;
		
		my $response; 
		my $json = {
			jsonrpc => $jsonRPC,
			method => "host.delete",
			params => {
				hostid => $hostID
			},
			auth => $authID,
			id => 1
		};
		$response = $client->call($zabbixApiURL, $json);
		
		# Check if response was successful	
		if($response->content->{'result'}) {
				return $response->content->{'result'};
				} else {
					logger("error","Delete Host failed.");
					return 0;
					}		
	}
	
	###############
	# Zabbix API existence host name
	#
	
	sub existNameHost {
		my ($name) = @_;
		
		my $response;
		my $json = {
			jsonrpc => $jsonRPC,
			method => "host.exists",
			params => {
			host => $name
			},
			auth => $authID,
			id => 1
		};
		$response = $client->call($zabbixApiURL, $json);
		
		return $response->content->{'result'};
	}
	
	###############
	# Zabbix API get hostgroups that the host belongs to
	#
	
	sub getHostgroupsOfHost {
		my ($hostID) = @_;
		
		my $response;
		my $json = {
			jsonrpc => $jsonRPC,
			method => "hostgroup.get",
			params => {
				output => "extend",
				hostids => [$hostID]
			},
			auth => $authID,
			id => 1
		};
		$response = $client->call($zabbixApiURL, $json);
		
		return $response->content->{'result'};
	}
	
	###############
	# Zabbix API change status
	# @Param : 
	#		$hostID : id of the host that needs a status update
	#		$status : can be '0' set the host to monitored, or '1' to set the host to not-monitored.
	# @Return : 	Returns the hostID as a scalar.
	#
	
	sub setStatusHost {
		my ($hostID, $status) = @_;
		
		# Make sure $status is 0 or 1 . 
		if($status != 0){
			$status = 1;
		}
		
		my $response;
		my $json = {
			jsonrpc => $jsonRPC,
			method => "host.update",
			params => {
				hostid => $hostID,
				status => $status
				},
				auth => $authID,
				id => 1
			};
		$response = $client->call($zabbixApiURL, $json);
		
		return $response->content->{'result'}->{'hostids'}[0];		
		
	}
	
	###############
	# Zabbix API add Host to Hostgroup
	# @Param : 
	#		$hostID : id of the host that needs to be added to a host group
	#		$hostgroupID : id of the host group the host needs to be added to
	# @Return : 	Returns the hostID as a scalar.
	#
	
	sub addHostToHostgroup {
		my ($hostID, $hostgroupID) = @_;
		
		my $response;
		my $json = {
			jsonrpc => $jsonRPC,
			method => "host.massadd",
			params => {
				hosts => [
					{
						hostid => $hostID
					}
				],
				groups => [
					{
						groupid => $hostgroupID
					}
				] 
				},
				auth => $authID,
				id => 1
			};
		$response = $client->call($zabbixApiURL, $json);

		# Check if response was successful	
		if($response->content->{'result'}) {
				return $response->content->{'result'}->{'hostids'}[0];
				} else {
					logger("error","Add Host to Hostgroup failed.");
					return 0;
					}
	}
	
	###############
	# Zabbix API remove Host from Hostgroup
	# @Param : 
	#		$hostID : id of the host that needs to be removed from a host group
	#		$hostgroupID : id of the host group the host needs to be removed from
	# @Return : 	Returns the hostID as a scalar.
	#
	sub removeHostFromHostgroup {
		my ($hostID, $hostgroupID) = @_;
		
		my $response;
		my $json = {
			jsonrpc => $jsonRPC,
			method => "host.massremove",
			params => {
				hostids => [$hostID],
				groupids => [$hostgroupID] 
				},
				auth => $authID,
				id => 1
			};
		$response = $client->call($zabbixApiURL, $json);
		# Check if response was successful	
		if($response->content->{'result'}) {
				return $response->content->{'result'}->{'hostids'}[0];
				} else {
					logger("error","Remove Host from Hostgroup failed.");
					return 0;
					}		
	}
	
	###############
	# Zabbix API link template to host
	# @Param : 
	#		$hostID : id of the host that needs to be added to a host group
	#		$hostgroupID : id of the host group the host needs to be added to
	# @Return : 	Returns the hostID as a scalar.
	#
	
	sub linkTemplateHost {
		my ($hostID, $templateID) = @_;
		
		my $response;
		my $json = {
			jsonrpc => $jsonRPC,
			method => "host.massadd",
			params => {
				hosts => [
					{
						hostid => $hostID
					}
				],
				templates => [
					{
						templateid => $templateID
					}
				] 
				},
				auth => $authID,
				id => 1
			};
		$response = $client->call($zabbixApiURL, $json);
		# Check if response was successful	
		if($response->content->{'result'}) {
				return $response->content->{'result'}->{'hostids'}[0];
				} else {
					logger("error","Link template to Host failed.");
					return 0;
					}	
	}
	

	###############
	# Zabbix API unlink templates from host
	# @Param :
	#		$hostID : id of the host that needs an update
	#		$templateID : Can be a scalar that contains an id or for multiple ids a structure like: [ {templateid => $templateID1}, {templateid => $templateID2} ];
	# @Return : 	Returns the hostID as a scalar.
	#
	
	sub unlinkTemplatesHost {
		my ($hostID, $templateID) = @_;
		
		my $response;
		my $json = {
			jsonrpc => $jsonRPC,
			method => "host.update",
			params => {
				hostid => $hostID,
				templates_clear => $templateID
				},
				auth => $authID,
				id => 1
			};
		$response = $client->call($zabbixApiURL, $json);
		
		# Check if response was successful	
		if($response->content->{'result'}) {
				return $response->content->{'result'}->{'hostids'}[0];
				} else {
					logger("error","Unlink template from Host failed.");
					return 0;
					}
		}
	
	
	
1;  # don't forget to return a true value from the file
