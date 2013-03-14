package Provisioning::Monitoring::Authentication;

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
	our @EXPORT = qw(login logout);
	
	# functions and variables which can be optionally exported
	our @EXPORT_OK = qw(getAuthID);
	
	}	

# Private
        
    my $client = new JSON::RPC::Client;
    my $authID;
    my $jsonRPC = "2.0";
        
    
# Public 
    
    ###############
    # Zabbix API authentication
    # 
    sub login {
	    my ($url, $user, $password) = @_;
	    
	    my $response;
	    my $json = {
		    jsonrpc => "2.0",
		    method => "user.login",
		    params => {
			    user => $user,
			    password => $password
		    },
		    id => 1
		    
	    };
	    
	    $response = $client->call($url, $json);
	    
	    # Check if response was successful
	    if($response->content->{'result'}) {
	    	$authID = $response->content->{'result'};
	    	logger("info", "Login successful.");
	    	} else {
	    		$authID = 0;
	    		logger("error", "Authentication failed, did not receive an authentication id from the Zabbix Server.");
	    		}
	    
	    return $authID;
		    
    }

    ###############
    # Zabbix API logout
    #
    sub logout {
	    my ($url, $auth) = @_;
	    
	    my $response;
	    my $json = {
		    jsonrpc => "2.0",
		    method => "user.logout",
		    params => {
		    },
		    id => 1,
		    auth => $auth
	    };
	    $response = $client->call($url, $json);
	    
	    # Check if response was successful
	    if($response->content->{'result'}) {
	    	$authID = 1;
	    	logger("info", "Logout successful.");
	    	} else {
	    		$authID = 0;
	    		logger("error", "Logout failed, did not receive a response from the Zabbix Server.");
	    		}	
	    
	    return $response->content->{'result'}; # True if successful.
	    
    }
    
# Optionally exported

    ###############
    # Get the current authentication id
    #
    sub getAuthID {
    	
    	return $authID;
    	}
    
    # END { ... }       # module clean-up code here (global destructor)
    1;  # don't forget to return a true value from the file