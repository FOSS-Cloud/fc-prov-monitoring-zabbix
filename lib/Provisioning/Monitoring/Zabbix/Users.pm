package Provisioning::Monitoring::Zabbix::Users;

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
	
	our %EXPORT_TAGS = ( 'all' => [ qw(initUsers createUser getUserID deleteUser listUsers) ] );
	
	# functions and variables which are exported by default
	our @EXPORT = qw(initUsers createUser getUserID deleteUser listUsers);
	
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

=item initUsers 

This method initialises some often used values in the module. I.e. a new json rpc client, the zabbix version (e.g. '2.0'), the authentication ID and the zabbix API url.
This method needs to be called before using any other method in the module, it's similar to a constructor in OO programming.

=item createUser

Creates a new usergroup. Returns the ID of the created host interface and '0' on failure.

=item deleteUser

Deletes the userwith the given name. Returns the id of the deleted user on success and '0' on failure.

=item getUser

Returns all user properties with a given ID. Or '0' on failure.

=cut

# Private
        
    my $client = new JSON::RPC::Client;
    my $jsonRPC;
    my $authID;
    my $zabbixApiURL;

# Constructor subroutine
	sub initUsers {
		my ($auth, $apiUrl, $rpcVersion) = @_;
		
		$authID = $auth;
		$zabbixApiURL = $apiUrl;
		$jsonRPC = $rpcVersion;
		
		return 1; 
		
		}
    
# Public 

	###############
	# Zabbix API create user
	#

	sub createUser {
		my ($aliasID, $name, $passwd, $usergroupID) = @_;
		
		if(readableAliasUser($aliasID) ne "true")
		{
			my $response;
			my $json = {
				jsonrpc => $jsonRPC,
				method => "user.create",
				params => {
					alias => $aliasID,
					passwd => $passwd,
					usrgrps => [
						{ usrgrpid => $usergroupID }
					],		
					name => $name
				},
				auth => $authID,
				id => 1
			};
			$response = $client->call($zabbixApiURL, $json);
			
			# Check if response was successful
			if($response->content->{'result'}) {
				return $response->content->{'result'}->{'userids'}[0];
				} else {
					logger("error","Create User failed.");
					return 0;
					}
				
			
			
		} else {
			logger("warning", "Tried creating a User that already exists with the same aliasID. Did not create a new User.");
			return getUserID($aliasID);
			
		}
			
	}

	###############
	# Zabbix API delete user group
	#

	sub deleteUser {
		my ($aliasID) = @_;
		
		if(writableAliasUser($aliasID) eq "true")
		{
			
			my $id = getUserID($aliasID);
			my $response;
			my $json = {
				jsonrpc => $jsonRPC,
				method => "user.delete",
				params => [
				{ userid => $id }
				],
				auth => $authID,
				id => 1
			};
			$response = $client->call($zabbixApiURL, $json);
			
			# Check if response was successful
			if($response->content->{'result'}) {
				return $response->content->{'result'}->{'userids'}[0];
				} else {
					logger("error","Delete user failed.");
					return 0;
					}	
			
		} else {
			logger("error","Can not delete the user $aliasID !");
			return 0;
		}
	}

	###############
	# Zabbix API get userID
	#

	sub getUserID {
		my ($aliasID) = @_;
		
		my $response;
		my $json = {
			jsonrpc => $jsonRPC,
			method => "user.get",
			params => { 
				output => ['userid'],
				filter => {
					alias => [
						$aliasID
					]
				       }
			},
			auth => $authID,
			id => 1
		};
		$response = $client->call($zabbixApiURL, $json);
		
		# Check if response was successful
		if($response->content->{'result'}) {
				return $response->content->{'result'}[0]->{'userid'};
				} else {
					logger("error","Get User id failed.");
					return 0;
					}	 
		
	}

	###############
	# Zabbix API check readability user
	#

	sub readableAliasUser {
		my ($aliasID) = @_;
		my $id = getUserID($aliasID);
		my $response;
		my $json = {
			jsonrpc => $jsonRPC,
			method => "user.isreadable",
			params => [
			$id
			],
			auth => $authID,
			id => 1
		};
		$response = $client->call($zabbixApiURL, $json);	
		
		# Check if response was successful
		if($response->content->{'result'}) {
				return $response->content->{'result'};  # true or false
				} else {
					logger("error","User doesn't exist!");
					return "false";
					}	 		
		
	}
	
	###############
	# Zabbix API check writability user
	#

	sub writableAliasUser {
		my ($aliasID) = @_;
		my $id = getUserID($aliasID);
		my $response;
		my $json = {
			jsonrpc => $jsonRPC,
			method => "user.iswritable",
			params => [
			$id
			],
			auth => $authID,
			id => 1
		};
		$response = $client->call($zabbixApiURL, $json);
		
		# Check if response was successful
		if($response->content->{'result'}) {
				return $response->content->{'result'};  # true or false
				} else {
					logger("error","User doesn't exist!");
					return "false";
					}		
		
	}
		
	
	###############
	# Zabbix API list all users on the Zabbix server
	#
	
	sub listUsers {
		my $response;
		my $json = {
			jsonrpc => $jsonRPC,
			method => "user.get",
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
					logger("error","List users failed.");
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

