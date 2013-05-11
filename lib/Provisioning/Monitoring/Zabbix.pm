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
my @zabbixUsergroups = ("Monitoring Administrator", "Monitoring User"); # List of allowed usergroups on the zabbix server

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
			
			# Handle changes in the ldap in the "people" subtree
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
		case  /^.+,ou=monitoring,ou=services,dc=foss-cloud,dc=org/  {
			# Check if the LDAP change is relevant to the Zabbix monitoring service
			return Provisioning::Monitoring::Zabbix::Constants::MONITORING_NOT_NEEDED unless (checkMonitoringService( $entry ) == Provisioning::Monitoring::Zabbix::Constants::TRUE);

			# If state is modifying, we probably get an entry from the modifyAttribute function, the processEntry can exit to prevent an endless loop. TODO: Solve this problem.
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
			
			# Check if ldap change is on a service or a unit (subservice).
			my @objectclass = getValue($entry, "objectClass"); 
			if( grep /labeledURIObject$/, @objectclass) {
				
				switch( $state )
				{
					case "adding" {
									$return_value = addSubService($entry);
									return Provisioning::Monitoring::Zabbix::Constants::ALREADY_EXIST_ON_ZABBIX unless $return_value != Provisioning::Monitoring::Zabbix::Constants::ALREADY_EXIST_ON_ZABBIX;
								}
					case "modifying" {
									# Not implemented yet
									return Provisioning::Monitoring::Zabbix::Constants::UNDEFINED_ERROR;
									}
					case "deleting" {
						
									$return_value = deleteSubService($entry);
									return Provisioning::Monitoring::Zabbix::Constants::ALREADY_DELETED_ON_ZABBIX unless $return_value != Provisioning::Monitoring::Zabbix::Constants::ALREADY_DELETED_ON_ZABBIX;
									}	
					else            {
									return Provisioning::Monitoring::Zabbix::Constants::WRONG_STATE_INFORMATION;
									}
				}
				
			} else {
								
				switch( $state )
				{
					case "adding" {
										$return_value = addService($entry);
										return Provisioning::Monitoring::Zabbix::Constants::ALREADY_EXIST_ON_ZABBIX unless $return_value != Provisioning::Monitoring::Zabbix::Constants::ALREADY_EXIST_ON_ZABBIX;
									}
					case "modifying" {
									# Not implemented yet
									return Provisioning::Monitoring::Zabbix::Constants::UNDEFINED_ERROR;
									}
					case "deleting" {

									$return_value = deleteService($entry);
									return Provisioning::Monitoring::Zabbix::Constants::ALREADY_DELETED_ON_ZABBIX unless $return_value != Provisioning::Monitoring::Zabbix::Constants::ALREADY_DELETED_ON_ZABBIX;
									}	
					else            {
									return Provisioning::Monitoring::Zabbix::Constants::WRONG_STATE_INFORMATION;
									}
				}
				
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
                                             Provisioning::Monitoring::Zabbix::Constants::WRONG_LDAP_SUBTREE,
                                             connectToBackendServer("connect",1)
                                           );  
                            return Provisioning::Monitoring::Zabbix::Constants::WRONG_LDAP_SUBTREE;
		}
		
	}
	
	# Should never come here.
	return Provisioning::Monitoring::Zabbix::Constants::UNDEFINED_ERROR;

}
# _____End processEntry sub




############################################################
# ----------------- Main handler methods ----------------- #
############################################################

#####
# Handle modification in the "people" subtree

sub peopleModificationHandler {
	
	my ( $entry, $state ) = @_;
	
	my $usergroupName = getValue($entry, "sstRole");

	return Provisioning::Monitoring::Zabbix::Constants::NO_MONITORING_USER unless ( grep /^$usergroupName$/, @zabbixUsergroups ); # Check if usergroup is relevant to the zabbix monitoring.
	# $state must be "adding", "modifying" or "deleting" otherwise something went wrong
	switch ( $state )
	{
	case "adding" {
					my $parent = getParentEntry( $entry );

					my $uid = getValue($parent, "uid");
					my $name = getValue($parent, "givenName");
					my $password = getValue($parent, "userPassword");
					my $usergroupID = 0;					
					
					# Create usergroup if it does not exist on the zabbix server
					if(existNameUsergroup($usergroupName) eq "false") {
						return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless createUsergroup($usergroupName) != 0;
					}
					$usergroupID = getUsergroupID($usergroupName);
					if($usergroupID == 0) {
						logger("error", "Did not get a usergroup ID from the Zabbix modules.");
						return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE;
					}
					
					# make sure the user is in the monitoring usergroup, despite if it already exists or not.
					if(readableAliasUser($uid) eq "true"){
						return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless addUserToUsergroup(getUserID($uid), $usergroupID) != 0;
					} else {
						return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless createUser($uid, $name, $password, $usergroupID) != 0;
					}
					
					# Add the user to customer usergroup
					my $customerEntry = getCustomerInfo(getValue($parent, "sstBelongsToCustomerUID"));
					$usergroupName = getValue($customerEntry, "uid")." - ".getValue($customerEntry, "o")."";
					if(existNameUsergroup($usergroupName) eq "false") {
							return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless createUsergroup($usergroupName) != 0;
						}
						$usergroupID = getUsergroupID($usergroupName);
						if($usergroupID == 0) {
							logger("error", "Did not get a usergroup ID from the Zabbix modules.");
							return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE;
						}
					return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless addUserToUsergroup(getUserID($uid), $usergroupID) != 0;
					
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
	my $groupName = getCustomerName( getValue($entry, "sstBelongsToCustomerUID") );
	
	#Create service hostgroup, if it does not exist.
	if(existNameHostGroup($service) eq "false") {
		return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless createHostGroup($service) != 0;
	}
	
	#Create customer hostgroup, if it does not exist.
	if(existNameHostGroup($groupName) eq "false") {
		return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless createHostGroup($groupName) != 0;
	}
	
	# Create customer usergroup, if it does not exist.
	if(existNameUsergroup($groupName) eq "false") {
		return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless createUsergroup($groupName) != 0;
	}
		
	return Provisioning::Monitoring::Zabbix::Constants::SUCCESS_CODE;	
}
#___End addService sub


#####
# Add a monitoring subservice
sub addSubService {
	
	my ( $entry ) = @_;
	
	my $subService = getValue($entry, "sstServiceName");
	return Provisioning::Monitoring::Zabbix::Constants::UNEXPECTED_LDAP_VALUE unless $subService eq "plus Monitoring Unit [per Unit]";
	my $labeledURI;
	my $parent = getParentEntry( $entry );
		
	# get ldap entry of unit
	my $member = getValue($entry, "member");
	if(defined($member)){
		$labeledURI = "ldap:///".$member."";
	} else {
		$labeledURI = getValue($entry, "labeledURI");
	}
	
	my $vmEntry = getVMEntry($labeledURI);
		
	# Generate unit hostname, as it should be used on the Zabbix server.
	my $vmName = getHostName($vmEntry); 
	
	# Check if unit exists on the zabbix server. 
	return Provisioning::Monitoring::Zabbix::Constants::ALREADY_EXIST_ON_ZABBIX unless existNameHost($vmName) eq "false";
	
	# Check if service (parent) is already provisioned, if not create it. (i.e. call the addService function again with the parent Entry)
	my $return_value = addService( $parent );
	return $return_value unless $return_value == 0;
	
	# Get customer hostgroup ID
	my $customerID = getValue($parent, "sstBelongsToCustomerUID");
	my $zabbixHostgroupID = getHostGroupID( getCustomerName($customerID) );
	
	# Generate template name, as it should be used on the Zabbix server.
	my @osResults = simpleSearch( getValue($vmEntry, "dn"), "(ou=operating system)", "sub");
	if ( @osResults != 1 )
	{
		logger("error","Multiple results after ldap search!");
		return Provisioning::Monitoring::Zabbix::Constants::MULTIPLE_RESULTS;
	} 
	my $templateName = "Template_".getValue($osResults[0], "sstOperatingSystem");
	my $zabbixTemplateID = getTemplateID($templateName);
	my $zabbixHostID;
	my $hostIP = "";
	
	if($zabbixTemplateID == 0){
		$zabbixHostID = createHost($vmName, $zabbixHostgroupID, $hostIP, $vmName);
		return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless $zabbixHostID != 0;
	} else {
		$zabbixHostID = createHostByTemplate($vmName, $zabbixHostgroupID, $zabbixTemplateID, $hostIP, $vmName);
		return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless $zabbixHostID != 0;
	}
	
	# Add host to service hostgroup
	return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless addHostToHostgroup($zabbixHostID, getHostGroupID( getValue($parent, "sstServiceName") )) != 0;

	return Provisioning::Monitoring::Zabbix::Constants::SUCCESS_CODE;
	
}
#___End addSubService sub

#####
# Delete a monitoring unit
sub deleteSubService {
	
	my ( $entry ) = @_;

	my $dn = getValue( $entry, "dn");
	my ($filter, $subtree) = split(/,/, $dn, 2);
	my @unitEntry = simpleSearch( $subtree, $filter, "sub");
	if ( @unitEntry != 1 )
	{
		logger("error","Multiple results after ldap search!");
		return Provisioning::Monitoring::Zabbix::Constants::MULTIPLE_RESULTS;
	} 
	
	# Check if it is part of the zabbix monitoring service.
	return Provisioning::Monitoring::Zabbix::Constants::MONITORING_NOT_NEEDED unless checkMonitoringService($unitEntry[0]) ==  Provisioning::Monitoring::Zabbix::Constants::TRUE;
		
	my $labeledURI = getValue($unitEntry[0], "labeledURI");
	my $vmEntry = getVMEntry($labeledURI);
	my $hostName = getHostName($vmEntry);
	
	# Check if the host still exists on the zabbix server, else it is already deleted.
	return Provisioning::Monitoring::Zabbix::Constants::ALREADY_DELETED_ON_ZABBIX unless existNameHost($hostName) eq "true";
	
	# Delete the host on the zabbix server.
	return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless deleteHost($hostName) != 0;
	
	return Provisioning::Monitoring::Zabbix::Constants::SUCCESS_CODE;
}
#___End deleteSubService sub

#####
# Delete a monitoring service
sub deleteService {
	
	my ( $entry ) = @_;
	
	# Get the service entry
	my $dn = getValue($entry, "dn");
	my ($filter, $subtree) = split(/,/, $dn, 2);
	my @serviceEntry = simpleSearch( $subtree, $filter, "sub");
	if ( @serviceEntry != 1 )
	{
		logger("error","Multiple results after ldap search!");
		return Provisioning::Monitoring::Zabbix::Constants::MULTIPLE_RESULTS;
	}
	
	# Check if it is part of the zabbix monitoring service.
	return Provisioning::Monitoring::Zabbix::Constants::MONITORING_NOT_NEEDED unless checkMonitoringService($serviceEntry[0]) ==  Provisioning::Monitoring::Zabbix::Constants::TRUE;
	
	# Get the service and groupname as it should be on the Zabbix server.
	my $service = getValue($serviceEntry[0], "sstServiceName");
	my $groupName = getCustomerName( getValue($serviceEntry[0], "sstBelongsToCustomerUID") );
	
	# Delete service hostgroup, if it exist.
	if(existNameHostGroup($service) eq "true") {
		return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless deleteHostGroup($service) != 0;
	}
	
	# Delete customer hostgroup, if it exist.
	if(existNameHostGroup($groupName) eq "true") {
		return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless deleteHostGroup($groupName) != 0;
	}
	
	# Delete customer usergroup, if it exist.
	if(existNameUsergroup($groupName) eq "true") {
		return Provisioning::Monitoring::Zabbix::Constants::GOT_ZERO_RETURN_FROM_ZABBIX_MODULE unless deleteUsergroup($groupName) != 0;
	}
		
	return Provisioning::Monitoring::Zabbix::Constants::SUCCESS_CODE;	
	
}
#___End deleteService sub




############################################################
# ----------------- LDAP and INFO methods ---------------- #
############################################################	

#####
# Check if sstIsActive is set on true in ldap

sub monitoringIsActive {
	my $subtree = "ou=configuration,ou=monitoring,ou=services,dc=foss-cloud,dc=org";
	my $filter = "(ou=prov-monitoring-zabbix)";
	
	my @results = simpleSearch( $subtree, $filter, "sub");
	
	if ( @results != 1 )
	{
		logger("error","Multiple results after ldap search!");
		return Provisioning::Monitoring::Zabbix::Constants::MULTIPLE_RESULTS; ;
		
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
	
	# If the @objectclass is not defined, this probably means an entry is deleted.
	if(! defined($objectclass[0])) {
		my $dn = getValue($entry, "dn");
		my ($filter, $subtree) = split(/,/, $dn, 2);
		my @results = simpleSearch( $subtree, $filter, "sub");
	
		if ( @results != 1 )
		{
			logger("error","Multiple results after ldap search!");
			return Provisioning::Monitoring::Zabbix::Constants::MULTIPLE_RESULTS; ;
		} 
		
		@objectclass = getValue($results[0], "objectClass");
	}
	
	# If the @objectclass is still not defined, we have a problem.
	if(! defined($objectclass[0])) {
		logger("error", "The entry does not have an objectClass!");
		return Provisioning::Monitoring::Zabbix::Constants::UNDEFINED_ERROR;
	}

	# Check if the objectclass is 'sstRoles' or 'sstProvisioning' (monitoring relevant)
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
# Get customer LDAP entry
sub getCustomerInfo {
	my ($customerID) = @_;
	
	my $subtree = "ou=customers,dc=foss-cloud,dc=org";
	my $filter = "(uid=$customerID)";
	
	my @custEntry = simpleSearch( $subtree, $filter, "sub");
	if ( @custEntry != 1 )
	{
		logger("error","Multiple results after ldap search!");
		return Provisioning::Monitoring::Zabbix::Constants::MULTIPLE_RESULTS;
	}
	
	return $custEntry[0];
}

#####
# Get customer name
sub getCustomerName {
	my ( $customerID ) = @_;
	
	my $customerEntry = getCustomerInfo($customerID);
	
	return getValue($customerEntry, "uid")." - ".getValue($customerEntry, "o")."";
}

#####
# Generate Hostname as it should be used on the Zabbix server
sub getHostName {
	my ( $entry ) = @_;
	
	# Generate unit hostname, as it should be used on the Zabbix server.
	return getValue($entry, "sstNetworkHostname").".".getValue($entry, "sstNetworkDomainName"); 	
}
#____End getHostName

#####
# Get the virtual machine entry in the ldap that is in the labeledURI
sub getVMEntry {
	
	my ( $labeledURI ) = @_;
	
	my ($ldap, $dn) = split(/\/\/\//, $labeledURI, 2); 
	my ($filter, $subtree) = split(/,/, $dn, 2);
	my @unitResults = simpleSearch( $subtree, $filter, "sub");
	if ( @unitResults != 1 )
	{
		logger("error","Multiple results after ldap search!");
	}
	
	return $unitResults[0];
}
#___End getVMEntry sub

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

=item 2013-05-09 Stijn Van Paesschen modified.

=item 2013-05-10 Stijn Van Paesschen modified.

Added the POD2text documentation.

=back

=cut

