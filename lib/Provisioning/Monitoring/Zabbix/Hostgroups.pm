package Provisioning::Monitoring::Zabbix::Hostgroups;

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

use Provisioning::Log;

BEGIN {
	require Exporter;
	
	# set the version for version checking
	our $VERSION = 1.00;
	
	# inherit from Exporter to export functions and variables
	our @ISA = qw(Exporter);
	
	# functions and variables which are exported by default
	our @EXPORT = qw(initHostgroups createHostGroup getHostGroupID deleteHostGroup listHostgroups);
	
	# functions and variables which can be optionally exported
	our @EXPORT_OK = qw(existNameHostGroup existIDHostGroup);
	
	}

=pod

=head1 Name

Hostgroups.pm

=head1 Synopsis

use Zabbixapi::Hostgroups;
initHostgroups($authenticationID, $url, $jsonRPC_client);

=head1 Description

This module contains all methods that are used to get information from or make change to Hostgroups on the Zabbix Server.

=head2 Uses

=over

=item Log

=item JSON::RPC::Client

=back

=head2 Methods

=over

=item initHostgroups 

This method initialises some often used values in the module. I.e. a new json rpc client, the zabbix version (e.g. '2.0'), the authentication ID and the zabbix API url.
This method needs to be called before using any other method in the module, it's similar to a constructor in OO programming.

=item createHostGroup 

Creates a new hostgroup with the given name. Returns the ID of the created hostgroup and '0' on failure.

=item deleteHostGroup

Deletes the hostgroup with the given id. Returns the id of the deleted hostgroup on success and '0' on failure.

=item getHostGroupID

Returns the hostgroup ID corresponding to a given name. Or '0' on failure.

=item existNameHostGroup

=item existIDHostGroup

=item listHostgroups

Returns all hostgroups that exist on the Zabbix server or '0' on failure. 

=cut						

# Private
        
    my $client = new JSON::RPC::Client;
    my $jsonRPC;
    my $authID;
    my $zabbixApiURL;

# Constructor subroutine
	sub initHostgroups {
		my ($auth, $apiUrl, $rpcVersion) = @_;
		
		$authID = $auth;
		$zabbixApiURL = $apiUrl;
		$jsonRPC = $rpcVersion;
		
		return 1; 
		
		}
    
# Public 

	###############
	# Zabbix API create host group
	#

	sub createHostGroup {
		my ($name) = @_;
		
		if(!existNameHostGroup($name))
		{
			my $response;
			my $json = {
				jsonrpc => $jsonRPC,
				method => "hostgroup.create",
				params => {
					name => $name
				},
				auth => $authID,
				id => 1
			};
			$response = $client->call($zabbixApiURL, $json);
			
			# Check if response was successful
			if($response->content->{'result'}) {
				return $response->content->{'result'}->{'groupids'}[0];
				} else {
					logger("error","Create Hostgroup failed.");
					return 0;
					}
				
			
			
		} else {
			logger("warning", "Tried creating a Hostgroup that already exists with the same name. Did not create a new Hostgroup.");
			return getHostGroupID($name);
			
		}
			
	}

	###############
	# Zabbix API delete host group
	#

	sub deleteHostGroup {
		my ($id) = @_;
		
		if(existIDHostGroup($id))
		{
			
			my $response;
			my $json = {
				jsonrpc => $jsonRPC,
				method => "hostgroup.delete",
				params => [
				$id
				],
				auth => $authID,
				id => 1
			};
			$response = $client->call($zabbixApiURL, $json);
			
			# Check if response was successful
			if($response->content->{'result'}) {
				return $response->content->{'result'}->{'groupids'}[0];
				} else {
					logger("error","Delete Hostgroup failed.");
					return 0;
					}	
			
		} else {
			logger("error","Can not delete Hostgroup, the Hostgroup id does not exist!");
			return 0;
		}
		
	}

	###############
	# Zabbix API get hostGroupID
	#

	sub getHostGroupID {
		my ($name) = @_;
		
		my $response;
		my $json = {
			jsonrpc => $jsonRPC,
			method => "hostgroup.get",
			params => { 
				output => ['groupid'],
				filter => {
					name => [
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
				return $response->content->{'result'}[0]->{'groupid'};
				} else {
					logger("error","Get Hostgroup id failed.");
					return 0;
					}	 
		
	}

	###############
	# Zabbix API check existence host group
	#

	sub existNameHostGroup {
		my ($name) = @_;
		
		my $response;
		my $json = {
			jsonrpc => $jsonRPC,
			method => "hostgroup.exists",
			params => {
			name => $name
			},
			auth => $authID,
			id => 1
		};
		$response = $client->call($zabbixApiURL, $json);	
		
		return $response->content->{'result'};
		
	}
	################

	sub existIDHostGroup {
		my ($id) = @_;
		
		my $response;
		my $json = {
			jsonrpc => $jsonRPC,
			method => "hostgroup.exists",
			params => {
				groupid => $id
				},
			auth => $authID,
			id => 1
		};
		$response = $client->call($zabbixApiURL, $json);

		return $response->content->{'result'};
		
	}
	
	
	###############
	# Zabbix API list all host groups on the Zabbix server
	#
	
	sub listHostgroups {
		my $response;
		my $json = {
			jsonrpc => $jsonRPC,
			method => "hostgroup.get",
			params => { 
				output => "extend",
			},
			auth => $authID,
			id => 1
		};
		$response = $client->call($zabbixApiURL, $json);
		
		# Check if response was successful
		if($response->content->{'result'}) {
				return $response->content->{'result'};
				} else {
					logger("error","List host groups failed.");
					return 0;
					}	
		}
	

	
1;  # don't forget to return a true value from the file

__END__
    
=back

=head1 Version

Created 2013 by Stijn Van Paesschen <stijn.van.paesschen@student.groept.be>

=over

=item 2013-02 Stijn Van Paesschen created.

=item 2013-03-27 Stijn Van Paesschen modified.

Added the POD2text documentation.

=back

=cut
