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

use Provisioning::Log;
use Provisioning::Backend::LDAP;
use Provisioning::Monitoring::Zabbix::Constants;

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
logger("info","The rpc url = $url");
my $apiuser = "4000002";  #TODO: be able to get Zabbix-Api admin out of LDAP
my $apipassword = "admin";
my $authID;
my $jsonRPC = "2.0";

# get the current service
my $service = $Provisioning::cfg->val("Global","SERVICE");

# get the config-file from the master script.
our $service_cfg = $Provisioning::cfg;

# load the nessecary modules
load "$Provisioning::server_module", ':all';



sub processEntry{

=pod

=over

=item processEntry($entry,$state)

=back

=cut

  my ( $entry, $state ) = @_;
  
  # Check if the LDAP change happened in a subtree that is relevant to the monitoring
  return Provisioning::Monitoring::Zabbix::Constants::MONITORING_NOT_NEEDED unless (checkObjectclass( $entry ) == Provisioning::Monitoring::Zabbix::Constants::TRUE);
  #return Provisioning::Monitoring::Zabbix::Constants::MONITORING_NOT_NEEDED unless (checkMonitoringService( $entry ) == Provisioning::Monitoring::Zabbix::Constants::TRUE);
      
  # If monitoring is not activated in the ldap, than exit the processEntry().
  return Provisioning::Monitoring::Zabbix::Constants::MONITORING_NOT_ACTIVE unless (monitoringIsActive() == Provisioning::Monitoring::Zabbix::Constants::TRUE);
  
  # Authenticate against Zabbix server, if not possible to authenticate return with error code.
  load "Provisioning::Monitoring::Zabbix::Authentication",':all';
  $authID = login($url, $apiuser, $apipassword);
  return Provisioning::Monitoring::Zabbix::Constants::AUTHENTICATION_FAILED unless ( $authID ne "0" );
  
  my $error = 0;

  	# Load and initialize Zabbix modules
	load "Provisioning::Monitoring::Zabbix::Usergroups",':all';
	logger("error","Init Usergroups failed") unless initUsergroups($authID, $url, $jsonRPC);
	load "Provisioning::Monitoring::Zabbix::Users",':all';
	logger("error","Init Users failed") unless initUsers($authID, $url, $jsonRPC);
	load "Provisioning::Monitoring::Zabbix::Templates",':all';
	logger("error","Init Templates failed") unless initTemplates($authID, $url, $jsonRPC);
	load "Provisioning::Monitoring::Zabbix::Hosts",':all';
	logger("error","Init Hosts failed") unless initHosts($authID, $url, $jsonRPC);
	load "Provisioning::Monitoring::Zabbix::Hostgroups",':all';
	logger("error","Init Hostgroups failed") unless initHostgroups($authID, $url, $jsonRPC);
	load "Provisioning::Monitoring::Zabbix::Hostinterfaces",':all';
	logger("error","Init Hostinterfaces failed") unless initHostinterfaces($authID, $url, $jsonRPC);

  
  # $state must be "add", "modify" or "delete" otherwise something went wrong
  my $originalState = $state;
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
		return Provisioning::Monitoring::Zabbix::Constants::CANNOT_CONNECT_TO_BACKEND;
	}
	
	# The return value that has to be returned to the backend
	my $return_value = 0;
	
	
	
	### Start Zabbix interaction
	my $subtree = getValue($entry, "dn");

	switch ( $subtree )
	{
		case /^.+,ou=people,dc=foss-cloud,dc=org/ {
			$return_value = peopleModificationHandler($entry, $state);
			print "people subtree \n";
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
		case  /^.+,ou=monitoring,ou=services,dc=foss-cloud,dc=org/  {
			# Check if the LDAP change is relevant to the Zabbix monitoring service
			return Provisioning::Monitoring::Zabbix::Constants::MONITORING_NOT_NEEDED unless (checkMonitoringService( $entry ) == Provisioning::Monitoring::Zabbix::Constants::TRUE);

				print "monitoring subtree \n";
				my $ent = getValue( $entry, "dn");
				print "monitoring: $ent \n";
				return Provisioning::Monitoring::Zabbix::Constants::SUCCESS_CODE unless $state ne "modifying";
			my $checkReturn;	

			# Write the changes to the backend
			$checkReturn = modifyAttribute( $entry, 
											 'sstProvisioningMode',
											 $state,
											 $write_connection
											);
											
			# Check if the sstProvisioningMode has been written, if not exit
			if( $checkReturn )
			{
				logger("error","Could not modify sstProvisioningMode!");
				return Provisioning::Monitoring::Zabbix::Constants::CANNOT_LOCK_MACHINE;
			}
			
			# Check if a service or a unit is added.
			my @objectclass = getValue($entry, "objectClass"); 
			if( grep /labeledURIObject$/, @objectclass) {
				print "This is a unit \n";
				$return_value = addSubService($entry);
			} else {
				print "This is a service \n";
				$return_value = addService($entry);
				
			}

			# Write the return code from the action 
			#modifyAttribute( $entry,
							   #'sstProvisioningReturnValue',
							   #$return_value,
							   #$write_connection
							 #);  
							 		 
			# Write the changes to the backend
			$checkReturn = modifyAttribute( $entry, 
											 'sstProvisioningMode',
											 $originalState,
											 $write_connection
											);
											
			# Check if the sstProvisioningMode has been written, if not exit
			if( $checkReturn )
			{
				logger("error","Could not modify sstProvisioningMode!");
				return Provisioning::Monitoring::Zabbix::Constants::CANNOT_LOCK_MACHINE;
			}

			# Disconnect from the backend
			disconnectFromServer($write_connection);
			return $return_value;
		}
		else {
			# Log the error and return error
                            logger("debug","The subtree for the entry "
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
                            return Provisioning::Monitoring::Zabbix::Constants::SUCCESS_CODE;
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


}
# _____End processEntry sub

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
# Check if change happened in subtree relevant for the monitoring.

sub checkObjectclass {
	my ( $entry ) = @_;
	
	my @objectclass = getValue($entry, "objectClass"); 
	
	if( grep /sstRoles$/, @objectclass) {
		return Provisioning::Monitoring::Zabbix::Constants::TRUE;
	} elsif ( grep /sstProvisioning$/, @objectclass ) {
		return Provisioning::Monitoring::Zabbix::Constants::TRUE;
	}
	return Provisioning::Monitoring::Zabbix::Constants::FALSE;	
}

#####
# Check if zabbix is selected as monitoring service

sub checkMonitoringService {
	my ( $entry ) = @_;
	
	return Provisioning::Monitoring::Zabbix::Constants::FALSE unless getValue($entry, "sstServiceProvisioningDaemon") eq "prov-monitoring-zabbix";
	
	return Provisioning::Monitoring::Zabbix::Constants::TRUE;
	
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
					my $parent = getParentEntry( $entry );

					my $uid = getValue($parent, "uid");
					my $name = getValue($parent, "givenName");
					my $password = getValue($parent, "userPassword");
					my $usergroupID = 0;
					
					# Check if there is a usergroup for the Zabbix Server
					# The two possibilities are: 'Monitoring Administrator' or 'User'					
					my $subtree = "uid=$uid,ou=people,dc=foss-cloud,dc=org";
					my $filter = "(sstRole=Monitoring Administrator)";
					my @results = simpleSearch( $subtree, $filter, "sub");
					my $usergroupName = getValue($entry, "sstRole");
					
					if ( $usergroupName eq "Monitoring Administrator" )
					{
						if(existNameUsergroup($usergroupName) eq "false") {
							return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless createUsergroup($usergroupName) != 0;
						}
						$usergroupID = getUsergroupID($usergroupName);
						if($usergroupID == 0) {
							logger("error", "Did not get a usergroup ID from the Zabbix modules.");
							return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE;
						}
					} elsif ( $usergroupName eq "Monitoring User" ) {
							if(existNameUsergroup($usergroupName) eq "false") {
								return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless createUsergroup($usergroupName) != 0;
							}
							$usergroupID = getUsergroupID($usergroupName);
							if($usergroupID == 0) {
								logger("error", "Did not get a usergroup ID from the Zabbix modules.");
								return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE;
							}
						} else {
							    logger("info", "Monitoring user should be Monitoring Administrator or User .");
								return Provisioning::Monitoring::Zabbix::Constants::NO_MONITORING_USER;
						}
					return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless createUser($uid, $name, $password, $usergroupID) != 0;
				}
	case "modifying" {
					logger("error", "Modifying a user is not implemented yet.");
					return Provisioning::Monitoring::Zabbix::Constants::UNDEFINED_ERROR;
						
					}
	case "deleting" {
					my $parent = getParentEntry( $entry );
					my $uid = getValue($parent, "uid");
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

#####
# Add a monitoring service
sub addService {
	my ( $entry ) = @_;
	
	
	my $service = getValue($entry, "sstServiceName");
	my $customerID = getValue($entry, "sstBelongsToCustomerUID");
	print "service = $service \n";
	#Create Hostgroup if it does not exist.
	my $zabbixHostgroupID = createHostGroup($service);
	return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless $zabbixHostgroupID != 0;
	
	#Create Usergroup if it does not exist.
	my $zabbixUsergroupID = createUsergroup($service);
	return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless $zabbixUsergroupID != 0;
	
	#Add every user to the usergroup.
	# my @results = simpleSearch("ou=people,dc=foss-cloud,dc=org", "(&(sstBelongsToCustomerUID=$customerID)(|(sstRole=Monitoring Administrator)(sstRole=Monitoring User)))", "sub");
	my @results = simpleSearch("ou=people,dc=foss-cloud,dc=org", "(sstBelongsToCustomerUID=$customerID)", "sub");
	print "simpleSearch people results: @results \n";
	foreach my $obj (@results) {
		my $personUID = getValue($obj, "uid");
		print "personUID = $personUID \n";
		my $zabbixUserID = getUserID( $personUID );
		print "zabbixUserID = $zabbixUserID \n";
		return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless $zabbixUserID != 0;
		return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless addUserToUsergroup($zabbixUserID, $zabbixUsergroupID) != 0;
	}
	print "Succes addService \n";
	return Provisioning::Monitoring::Zabbix::Constants::SUCCESS_CODE;	
}
#___End addService sub


#####
# Add a monitoring subservice
sub addSubService {
	my ( $entry ) = @_;
	
	my $subService = getValue($entry, "sstServiceName");
	return Provisioning::Monitoring::Zabbix::Constants::UNEXPECTED_LDAP_VALUE unless $subService eq "plus Monitoring Unit [per Unit]";
	my $labeledURI = getValue($entry, "labeledURI");
		
	#Create Hostgroup if it does not exist, if it exist get the ID.
	my $parentService = getValue(getParentEntry( $entry ), "sstServiceName");
	my $zabbixHostgroupID = createHostGroup($parentService);
	return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless $zabbixHostgroupID != 0;
	
	# Check if the labeled URI resulted in an attribute 'member'
	my $member = getValue($entry, "member");
	my $ldap;
	($ldap, $member) = split(/\/\/\//, $labeledURI, 2) unless defined($member); # Get dn out of labeledURI and put it in $member, unless 'member' is present as an attribute.
	my ($unit, $subtree) = split(/,/, $member, 2);
	
	my @unitResults = simpleSearch( $subtree, $unit, "sub");
	if ( @unitResults != 1 )
	{
		logger("error","Multiple results after ldap search!");
		return Provisioning::Monitoring::Zabbix::Constants::MULTIPLE_RESULTS;
	} 
	
	# Generate virtual machine hostname, as it should be used on the Zabbix server.
	my $vmName = getValue($unitResults[0], "sstNetworkHostname").".".getValue($unitResults[0], "sstNetworkDomainName"); 
	
	my @osResults = simpleSearch( $member, "(ou=operating system)", "sub");
	if ( @osResults != 1 )
	{
		logger("error","Multiple results after ldap search!");
		return Provisioning::Monitoring::Zabbix::Constants::MULTIPLE_RESULTS;
	} 
	my $templateName = "Template_".getValue($osResults[0], "sstOperatingSystem");
	my $zabbixTemplateID = getTemplateID($templateName);
	
	
	if($zabbixTemplateID == 0){
		return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless createHost($vmName, $zabbixHostgroupID, "", $vmName) != 0;
	} else {
		return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless createHostByTemplate($vmName, $zabbixHostgroupID, $zabbixTemplateID, "", $vmName) != 0;
	}
		
	return Provisioning::Monitoring::Zabbix::Constants::SUCCESS_CODE;
	
}
#___End addSubService sub

1;

__END__
    
=back

=head1 Version

Created 2013 by Stijn Van Paesschen <stijn.van.paesschen@student.groept.be>

=over

=item 2013-03-22 Stijn Van Paesschen created.

=item 2013-03-27 Stijn Van Paesschen modified.

=item 2013-05-07 Stijn Van Paesschen modified.

=item 2013-05-08 Stijn Van Paesschen modified.

Added the POD2text documentation.

=back

=cut

