package Provisioning::Monitoring::Hostinterfaces;

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
	our @EXPORT = qw(initHostinterfaces getHostInterface);
	
	# functions and variables which can be optionally exported
	our @EXPORT_OK = qw(createHostInterface deleteHostInterface);
	
	}

=pod

=head1 Name

Hostgroups.pm

=head1 Synopsis

use Zabbixapi::Hostgroups;
initHostinterfaces($authenticationID, $url, $jsonRPC_client);

=head1 Description

This module contains all methods that are used to get information from or make change to Hostinterfaces on the Zabbix Server.

=head2 Uses

=over

=item Log

=item JSON::RPC::Client

=back

=head2 Methods

=over

=item initHostinterfaces 

This method initialises some often used values in the module. I.e. a new json rpc client, the zabbix version (e.g. '2.0'), the authentication ID and the zabbix API url.
This method needs to be called before using any other method in the module, it's similar to a constructor in OO programming.

=item createHostInterface 

Creates a new host interface for a given host (id), ip address and port number. Returns the ID of the created host interface and '0' on failure.

=item deleteHostInterface

Deletes the host interface with the given id. Returns the id of the deleted host interface on success and '0' on failure.

=item getHostInterface

Returns all Host Interface properties for a Host Interface with a given ID. Or '0' on failure.

=cut						
			

# Private
        
    my $client = new JSON::RPC::Client;
    my $jsonRPC;
    my $authID;
    my $zabbixApiURL;

# Constructor subroutine
	sub initHostinterfaces {
		my ($auth, $apiUrl, $rpcVersion) = @_;
		
		$authID = $auth;
		$zabbixApiURL = $apiUrl;
		$jsonRPC = $rpcVersion;
		
		return 1; 
		
		}
    
# Public 

	###############
	# Zabbix API create interface
	#

	sub createHostInterface {
		my ($hostID, $ip, $port) = @_;
		
		my $response;
		my $json = {
			jsonrpc => $jsonRPC,
			method => "hostinterface.create",
			params => {
				hostid => $hostID,
				dns => "",
				ip => $ip,
				main => 0,
				port => $port,
				type => 1,
				useip => 1
			},
			auth => $authID,
			id => 1
		};
		$response = $client->call($zabbixApiURL, $json);
		
		# Check if response was successful	
		if($response->content->{'result'}) {
				return $response->content->{'result'}->{'interfaceids'}[0];
				} else {
					logger("error","Create Host interface failed.");
					return 0;
					}
	}

	###############
	# Zabbix API delete interface
	#

	sub deleteHostInterface {
		my ($interfaceID) = @_;
		
		my $response;
		my $json = {
			jsonrpc => $jsonRPC,
			method => "hostinterface.delete",
			params => [
			$interfaceID
			],
			auth => $authID,
			id => 1
		};
		$response = $client->call($zabbixApiURL, $json);
		
		# Check if response was successful	
		if($response->content->{'result'}) {
				return $response->content->{'result'}->{'interfaceids'}[0];
				} else {
					logger("error","Delete Host interface failed.");
					return 0;
					}		
	}

	###############
	# Zabbix API get interface
	#

	sub getHostInterface {
		my ($hostID) = @_;
		
		my $response;
		my $json = {
			jsonrpc => $jsonRPC,
			method => "hostinterface.get",
			params => {
				hostids => $hostID
			},
			auth => $authID,
			id => 1
		};
		$response = $client->call($zabbixApiURL, $json);
		
		# Check if response was successful	
		if($response->content->{'result'}) {
				return $response->content->{'result'};
				} else {
					logger("error","Get Host interface failed.");
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
