package Provisioning::Monitoring::Zabbix::Templates;

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
	our @EXPORT = qw(initTemplates getTemplateID listTemplates);
	
	# functions and variables which can be optionally exported
	our @EXPORT_OK = qw();
	
	}

=pod

=head1 Name

Hostgroups.pm

=head1 Synopsis

use Zabbixapi::Hostgroups;
initTemplates($authenticationID, $url, $jsonRPC_client);

=head1 Description

This module contains all methods that are used to get information from or make change to templates on the Zabbix Server.

=head2 Uses

=over

=item Log

=item JSON::RPC::Client

=back

=head2 Methods

=over

=item initTemplates 

This method initialises some often used values in the module. I.e. a new json rpc client, the zabbix version (e.g. '2.0'), the authentication ID and the zabbix API url.
This method needs to be called before using any other method in the module, it's similar to a constructor in OO programming.

=item getTemplateID 

Returns the template ID with a given name.

=item listTemplates

Returns all templates that exist on the Zabbix server.

=cut				

# Private
        
    my $client = new JSON::RPC::Client;
    my $jsonRPC;
    my $authID;
    my $zabbixApiURL;

# Constructor subroutine
	sub initTemplates {
		my ($auth, $apiUrl, $rpcVersion) = @_;
		
		$authID = $auth;
		$zabbixApiURL = $apiUrl;
		$jsonRPC = $rpcVersion;
		
		return 1; 
		
		}
    
# Public 

	###############
	# Zabbix API get TemplateID
	#

	sub getTemplateID {
		my ($name) = @_;
		
		my $response;
		my $json = {
			jsonrpc => $jsonRPC,
			method => "template.get",
			params => { 
				output => "extend",
				filter => {
					host => [
						$name 
					]
				},
	
			},
			auth => $authID,
			id => 1
		};
		$response = $client->call($zabbixApiURL, $json);
		
		# Check if response was successful	
		if($response->content->{'result'}) {
				return $response->content->{'result'}[0]->{'templateid'};
				} else {
					logger("error","Get Template failed.");
					return 0;
					}		
	}
	
	
	###############
	# Zabbix API list all templates on the Zabbix server
	#
	
	sub listTemplates {
		my $response;
		my $json = {
			jsonrpc => $jsonRPC,
			method => "template.get",
			params => { 
				output => "extend"
	
			},
			auth => $authID,
			id => 1
		};
		$response = $client->call($zabbixApiURL, $json);
			
		# Check if response was successful	
		if($response->content->{'result'}) {
				return $response->content->{'result'};
				} else {
					logger("error","List Templates failed.");
					return 0;
					}
		}
	
1; # Return 1

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
