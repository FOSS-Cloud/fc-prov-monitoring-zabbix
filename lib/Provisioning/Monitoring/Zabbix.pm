package Provisioning::Monitoring::Zabbix;

# Copyright (C) 2012 FOSS-Group
#                    Germany
#                    http://www.foss-group.de
#                    support@foss-group.de
#
# Authors:
#  Stijn Van Paesschen <stijn.van.paesschen@student.groept.be>
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

use warnings;
use strict;

use Config::IniFiles;
use Module::Load;
use Switch;
use JSON::RPC::Client;

use Provisioning::Log;

use Provisioning::Backend::LDAP;
use Provisioning::Monitoring::Zabbix::Constants;

use Provisioning::Monitoring::Zabbix::Templates;
use Provisioning::Monitoring::Zabbix::Hosts;
use Provisioning::Monitoring::Zabbix::Hostgroups;
use Provisioning::Monitoring::Zabbix::Hostinterfaces;
use Provisioning::Monitoring::Zabbix::Authentication;
use Provisioning::Monitoring::Zabbix::Usergroups;
use Provisioning::Monitoring::Zabbix::Users;


require Exporter;

=pod

=head1 Name

Zabbix.pm

=head1 Description

=head1 Methods

=cut


our @ISA = qw(Exporter);

our %EXPORT_TAGS = ( 'all' => [ qw(processEntry) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(processEntry);

our $VERSION = '0.01';


###############################################################################
#####                             Constants                               #####
###############################################################################

my $url = getRpcUrl();
print "url = $url \n";
my $client = new JSON::RPC::Client;
my $apiuser = "4000002";  #TODO: be able to get Zabbix-Api admin out of LDAP
my $apipassword = "admin";
my $authID;
my $jsonRPC = "2.0";

#Authenticate against Zabbix server
$authID = login($url, $apiuser, $apipassword);

# Initialize modules
logger("error","Init Hosts failed") unless initHosts($authID, $url, $jsonRPC);
logger("error","Init Hostgroups failed") unless initHostgroups($authID, $url, $jsonRPC);
logger("error","Init Hostinterfaces failed") unless initHostinterfaces($authID, $url, $jsonRPC);
logger("error","Init Templates failed") unless initTemplates($authID, $url, $jsonRPC);
logger("error","Init Usergroups failed") unless initUsergroups($authID, $url, $jsonRPC);
logger("error","Init Users failed") unless initUsers($authID, $url, $jsonRPC);


# get the current service
my $service = $Provisioning::cfg->val("Global","SERVICE");

# get the config-file from the master script.
our $service_cfg = $Provisioning::cfg;

# load the nessecary modules
load "$Provisioning::server_module", ':all';

print "before processEntry\n";

sub processEntry{
print "enter processEntry. \n";
=pod

=over

=item processEntry($entry,$state)

=back

=cut

  my ( $entry, $state ) = @_;
  
  # If monitoring is not activated in the ldap, than exit the processEntry().
  return Provisioning::Monitoring::Zabbix::Constants::SUCCESS_CODE unless (monitoringIsActive() == Provisioning::Monitoring::Zabbix::Constants::TRUE);
  
  my $error = 0;
  
  
	load "Provisioning::Monitoring::Zabbix::Usergroups",':all';
	initUsergroups($authID, $url, $jsonRPC);
	load "Provisioning::Monitoring::Zabbix::Users",':all';
	initUsers($authID, $url, $jsonRPC);
  
  
  
  # $state must be "add", "modify" or "delete" otherwise something went wrong
  switch ( $state )
{
	case "add" {
					# First of all we need to let the deamon know that we 
                    # saw the change in the backend and the process is  
                    # started. So write adding to sstProvisioningMode.
                    $state = "adding";
				}
	case "modify" {
					# First of all we need to let the deamon know that we 
                    # saw the change in the backend and the process is  
                    # started. So write modifying to sstProvisioningMode.
                    $state = "modifying";
					}
	case "delete" {
					# First of all we need to let the deamon know that we 
                    # saw the change in the backend and the process is  
                    # started. So write deleting to sstProvisioningMode.
                    $state = "deleting";
					}	
	else            {
                            # Log the error and return error
                            logger("error","The state for the entry "
                                   .getValue($entry,"dn")." is $state. Can only"
                                   ." process entries with one of the following"
                                   ." states: \"add\", \"modify\", " 
                                   ."\"delete\"");

                            # Write the return code from the action 
                            modifyAttribute( $entry,
                                             'sstProvisioningReturnValue',
                                             Provisioning::Monitoring::Zabbix::Constants::WRONG_STATE_INFORMATION,
                                             connectToBackendServer("connect",1)
                                           );  
                            return Provisioning::Monitoring::Zabbix::Constants::WRONG_STATE_INFORMATION;
                    }
  			
	}
	
	# Connect to the backend
	my $write_connection = connectToBackendServer("connect",1);

	# Check if connection is established
	unless ( $write_connection )
	{
		logger("error","Could not connect to the backend!");
		#return Provisioning::Monitoring::Zabbix::Constants::CANNOT_CONNECT_TO_BACKEND;
		return -1;
	}
	
	# The return value that has to be returned to the backend
	my $return_value = 0;
	
	# Write the changes to the backend
	$return_value = modifyAttribute( $entry, 
									 'sstProvisioningMode',
									 $state,
									 $write_connection
									);
									
	# Check if the sstProvisioningMode has been written, if not exit
	if( $return_value )
	{
		logger("error","Could not modify sstProvisioningMode!");
		#return Provisioning::Monitoring::Zabbix::Constants::CANNOT_LOCK_MACHINE;
		return -1;
	}
	
	
	### Start Zabbix part
	my $subtree = getValue($entry, "dn");
	
	switch ( $subtree )
	{
		case "^.+,ou=people,dc=foss-cloud,dc=org" {
			$return_value = peopleModificationHandler($entry, $state);
			# Write the return code from the action 
			modifyAttribute( $entry,
							   'sstProvisioningReturnValue',
							   $return_value,
							   $write_connection
							 );  

			# Disconnect from the backend
			disconnectFromServer($write_connection);

			return $return_value;
		}
		case  "^.+, ou=monitoring,ou=services,dc=foss-cloud,dc=org"  {
			return Provisioning::Monitoring::Zabbix::Constants::UNDEFINED_ERROR;
		}
		else {
			# Log the error and return error
                            logger("error","The subtree for the entry "
                                   .getValue($entry,"dn")." is $subtree. Can only"
                                   ." process entries with one of the following"
                                   ." subtrees: \"ou=people,dc=foss-cloud,dc=org\", \"ou=monitoring,ou=services,dc=foss-cloud,dc=org\"" 
                                   );

                            # Write the return code from the action 
                            modifyAttribute( $entry,
                                             'sstProvisioningReturnValue',
                                             Provisioning::Monitoring::Zabbix::Constants::UNDEFINED_ERROR,
                                             connectToBackendServer("connect",1)
                                           );  
                            return Provisioning::Monitoring::Zabbix::Constants::UNDEFINED_ERROR;
		}
		
	}
	
	

  # Do your stuff here ...

  # If you want to Log something use the logger(level,message) method from the 
  # Provisioning::Log module

  # If you want to execute a command on a system use the 
  # executeCommand(connection,args[]) method from the Provisioning::TransportAPI
  # ::<API> module (also use this module for connect disconnect etc)

  # Also use the Provisioning::Backend::<Backend> module for everything
  # concerning the backend (connect disconnect search etc) 


} # end sub processEntry

##### Zabbix Methods

sub addHost {
	
	my ($vmID) = @_;
	
	my @infoOS = getInfoOS($vmID);
	my $OSName = $infoOS[0];
	my $OSType = $infoOS[1];
	my $OSVersion = $infoOS[2];
	
	my $hostgroupName = "$OSName server";
	my $hostgroupID = getHostGroupID($hostgroupName);
	if($hostgroupID == 0) {
		$hostgroupID = getHostGroupID("Discovered hosts");
	}
	
	my $templateName = "Template OS $OSName";
	my $templateID = getTemplateID($templateName);
	if($templateID == 0) {
		return createHost($vmID, $hostgroupID); #Hopefully returns Zabbix Host ID
	} else {
		return createHostByTemplate($vmID, $hostgroupID, $templateID); #Hopefully returns Zabbix Host ID
	}
	
	
}

##### Ldap Methods

sub getInfoOS {
	
	my ( $VirtualMachineID ) = @_;
	
	my $subtree = "sstVirtualMachine=$VirtualMachineID,ou=virtual machines,ou=virtualization,ou=services,dc=foss-cloud,dc=org";
	my $filter = "(ou=operating system)";
	
	my @results = simpleSearch( $subtree, $filter, "sub");
	
	if ( @results != 1 )
	{
		logger("error","Multiple results after ldap search!");
		#return Provisioning::Monitoring::Zabbix::Constants::MULTIPLE_RESULTS;
		return -1;
		
	} else {
		my @OSinfo = (getValue($results[0], "sstOperatingSystem"), getValue($results[0], "sstOperatingSystemType"), getValue($results[0], "sstOperatingSystemVersion")); #E.g. (Linux, Fedora, 18) or (Windows, undef, 2008 R2)
		return @OSinfo;
	}
	
	
}

###

#####
# Check if sstIsActive is set on true in ldap

sub monitoringIsActive {
	my $subtree = "ou=configuration,ou=monitoring,ou=services,dc=foss-cloud,dc=org";
	my $filter = "(ou=prov-monitoring-zabbix)";
	
	my @results = simpleSearch( $subtree, $filter, "sub");
	
	if ( @results != 1 )
	{
		my $errCode = Provisioning::Monitoring::Zabbix::Constants::MULTIPLE_RESULTS; 
		logger("error","Multiple results after ldap search! Error: $errCode .");
		return Provisioning::Monitoring::Zabbix::Constants::FALSE;
		
	} else {
		return Provisioning::Monitoring::Zabbix::Constants::FALSE unless getValue($results[0], "sstIsActive") eq "TRUE";
		return Provisioning::Monitoring::Zabbix::Constants::TRUE;
	}
	
}

#####
# Get Zabbix jsonrpc url
# Returns url or False, if sstIsActive = False

sub getRpcUrl {
	my $subtree = "ou=configuration,ou=monitoring,ou=services,dc=foss-cloud,dc=org";
	my $filter = "(ou=prov-monitoring-zabbix)";
	
	my @results = simpleSearch( $subtree, $filter, "sub");
	if ( @results != 1 )
	{
		my $errCode = Provisioning::Monitoring::Zabbix::Constants::MULTIPLE_RESULTS; 
		logger("error","Multiple results after ldap search! Error: $errCode .");
		return Provisioning::Monitoring::Zabbix::Constants::FALSE;
		
	} elsif ( getValue($results[0], "sstIsActive") ne "TRUE") {			# If sstIsActive = false, then return FALSE.
		return Provisioning::Monitoring::Zabbix::Constants::FALSE;
	
	} else {
		return getValue($results[0], "sstWebsiteURL");
	}
	
}

#####
# Handle modification in the "people" subtree

sub peopleModificationHandler {
	my ( $entry, $state ) = @_;	
	
	# $state must be "adding", "modifying" or "deleting" otherwise something went wrong
	switch ( $state )
	{
	case "adding" {
				
					my $uid = getValue($entry, "User Name");

					print "uid = $uid\n";
					my $name = getValue($entry, "givenName");

					print "$name \n";
					my $password = getValue($entry, "Password");

					print "$password \n";
					my $usergroupID = 0;
					
					my $subtree = "uid=$uid,ou=people,dc=foss-cloud,dc=org";
					my $filter = "(sstRole=Monitoring Administrator)";
	
					my @results = simpleSearch( $subtree, $filter, "sub");
					
					if ( @results != 1 )
					{
						logger("error","Multiple results after ldap search!");
						return Provisioning::Monitoring::Zabbix::Constants::MULTIPLE_RESULTS;
						
					} else {
						my $usergroupName = getValue($results[0], "sstRole");
						if(existNameUsergroup($usergroupName) eq "false") {
							return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless createUsergroup($usergroupName) != 0;
						}
						$usergroupID = getUsergroupID($usergroupName);
						if($usergroupID == 0) {
							logger("error", "Did not get a usergroup ID from the Zabbix modules.");
							return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE;
						}
					}
					
					return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless createUser($uid, $name, $password, $usergroupID) != 0;
				}
	case "modifying" {
					logger("error", "Modifying a user is not implemented yet.");
					return Provisioning::Monitoring::Zabbix::Constants::UNDEFINED_ERROR;
						
					}
	case "deleting" {
					my $uid = getValue($entry, "User Name");
					return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless deleteUser($uid) != 0;
					}	
	else            {
                            # Log the error and return error
                            logger("error","The state is $state. But can only"
                                   ." process entries with one of the following"
                                   ." states: \"adding\", \"modifying\", " 
                                   ."\"deleting\"");

                            return Provisioning::Monitoring::Zabbix::Constants::WRONG_STATE_INFORMATION;
                            
                    }
	}	
	return Provisioning::Monitoring::Zabbix::Constants::SUCCESS_CODE;
}
#___End peopleModificationHandler sub



1;

__END__
    
=back

=head1 Version

Created 2013 by Stijn Van Paesschen <stijn.van.paesschen@student.groept.be>

=over

=item 2013-03-22 Stijn Van Paesschen created.

=item 2013-03-27 Stijn Van Paesschen modified.

Added the POD2text documentation.

=back

=cut

