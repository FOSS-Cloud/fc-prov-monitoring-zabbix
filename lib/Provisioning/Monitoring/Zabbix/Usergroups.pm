package Provisioning::Monitoring::Zabbix::Usergroups;

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
	
	our %EXPORT_TAGS = ( 'all' => [ qw(initUsergroups createUsergroup getUsergroupID deleteUsergroup existNameUsergroup) ] );
	
	# functions and variables which are exported by default
	our @EXPORT = qw(initUsergroups createUsergroup getUsergroupID deleteUsergroup existNameUsergroup);
	
	# functions and variables which can be optionally exported
	our @EXPORT_OK = qw();
	
	}

=pod

=head1 Name

Usergroups.pm

=head1 Synopsis

use Provisioning::Monitoring::Zabbix::Usergroups;
initUsergroups($authenticationID, $url, $jsonRPC_client);

=head1 Description

This module contains all methods that are used to get information from or make change to Usergroups on the Zabbix Server.

=head2 Uses

=over

=item Log

=item JSON::RPC::Client

=back

=head2 Methods

=over

=item initUsergroups 

This method initialises some often used values in the module. I.e. a new json rpc client, the zabbix version (e.g. '2.0'), the authentication ID and the zabbix API url.
This method needs to be called before using any other method in the module, it's similar to a constructor in OO programming.

=item createUsergroup 

Creates a new usergroup. Returns the ID of the created host interface and '0' on failure.

=item deleteUsergroup

Deletes the usergroup with the given name. Returns the id of the deleted host interface on success and '0' on failure.

=item getUsergroup

Returns all usergroup properties with a given ID. Or '0' on failure.

=cut

# Private
        
    my $client = new JSON::RPC::Client;
    my $jsonRPC;
    my $authID;
    my $zabbixApiURL;

# Constructor subroutine
	sub initUsergroups {
		my ($auth, $apiUrl, $rpcVersion) = @_;
		
		$authID = $auth;
		$zabbixApiURL = $apiUrl;
		$jsonRPC = $rpcVersion;
		
		return 1; 
		
		}
    
# Public 

	###############
	# Zabbix API create user group
	#

	sub createUsergroup {
		my ($name) = @_;
		
		if(!existNameUsergroup($name))
		{
			my $response;
			my $json = {
				jsonrpc => $jsonRPC,
				method => "usergroup.create",
				params => {
					name => $name
				},
				auth => $authID,
				id => 1
			};
			$response = $client->call($zabbixApiURL, $json);
			
			# Check if response was successful
			if($response->content->{'result'}) {
				return $response->content->{'result'}->{'usrgrpids'}[0];
				} else {
					logger("error","Create Usergroup failed.");
					return 0;
					}
				
			
			
		} else {
			logger("warning", "Tried creating a Usergroup that already exists with the same name. Did not create a new Usergroup.");
			return getUsergroupID($name);
			
		}
			
	}

	###############
	# Zabbix API delete user group
	#

	sub deleteUsergroup {
		my ($name) = @_;
		
		if(existNameUsergroup($name))
		{
			
			my $id = getUsergroupID($name);
			my $response;
			my $json = {
				jsonrpc => $jsonRPC,
				method => "usergroup.delete",
				params => [
				$id
				],
				auth => $authID,
				id => 1
			};
			$response = $client->call($zabbixApiURL, $json);
			
			# Check if response was successful
			if($response->content->{'result'}) {
				return $response->content->{'result'}->{'usrgrpids'}[0];
				} else {
					logger("error","Delete usergroup failed.");
					return 0;
					}	
			
		} else {
			logger("error","Can not delete usergroup, the usergroup does not exist!");
			return 0;
		}
		
	}

	###############
	# Zabbix API get usergroupID
	#

	sub getUsergroupID {
		my ($name) = @_;
		if(existNameUsergroup($name) eq "false"){
			logger("Error","Can not get Usergroup id. Usergroup = $name does not exist!");
			return 0;
		}
		my $response;
		my $json = {
			jsonrpc => $jsonRPC,
			method => "usergroup.get",
			params => { 
				output => ['usrgrpid'],
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
		if(defined $response) {
				return $response->content->{'result'}[0]->{'usrgrpid'};
				} else {
					logger("error","Get Usergroup id failed.");
					return 0;
					}	 
		
	}

	###############
	# Zabbix API check existence host group
	#

	sub existNameUsergroup {
		my ($name) = @_;
		
		my $response;
		my $json = {
			jsonrpc => $jsonRPC,
			method => "usergroup.exists",
			params => {
			name => $name
			},
			auth => $authID,
			id => 1
		};
		$response = $client->call($zabbixApiURL, $json);	
		
		return $response->content->{'result'};  #true or false
		
	}
		
	
	###############
	# Zabbix API list all host groups on the Zabbix server
	#
	
	sub listUsergroups {
		my $response;
		my $json = {
			jsonrpc => $jsonRPC,
			method => "usergroup.get",
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
					logger("error","List user groups failed.");
					return 0;
					}	
		}
	


1;  # don't forget to return a true value from the file

__END__
    
=back

=head1 Version

Created 2013 by Stijn Van Paesschen <stijn.van.paesschen@student.groept.be>

=over

=item 2013-04-23 Stijn Van Paesschen created.

=back

=cut				
