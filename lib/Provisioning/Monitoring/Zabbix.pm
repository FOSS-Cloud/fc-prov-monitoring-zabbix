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

use Provisioning::Monitoring::Templates;
use Provisioning::Monitoring::Hosts;
use Provisioning::Monitoring::Hostgroups;
use Provisioning::Monitoring::Hostinterfaces;
use Provisioning::Monitoring::Authentication;


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

my $url = "http://127.0.0.1/zabbix/api_jsonrpc.php";
my $client = new JSON::RPC::Client;
my $apiuser = "Admin";
my $apipassword = "zabbix";
my $authID;
my $jsonRPC = "2.0";

#Authenticate against Zabbix server
login($url, $apiuser, $apipassword);
$authID = Zabbixapi::Authentication::getAuthID();
print "Authentication successful. Auth ID: " . $authID . "\n";

# Initialize modules
logger("error","Init Hosts failed") unless initHosts($authID, $url, $jsonRPC);
logger("error","Init Hostgroups failed") unless initHostgroups($authID, $url, $jsonRPC);
logger("error","Init Hostinterfaces failed") unless initHostinterfaces($authID, $url, $jsonRPC);
logger("error","Init Templates failed") unless initTemplates($authID, $url, $jsonRPC);


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
  
  
  my $error = 0;
  
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
                                             #Provisioning::Monitoring::Zabbix::Constants::WRONG_STATE_INFORMATION,
                                             -1,
                                             connectToBackendServer("connect",1)
                                           );  
                            #return Provisioning::Monitoring::Zabbix::Constants::WRONG_STATE_INFORMATION;
                            return -1;
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
	
	
	# Test scenario: problem
	# Problem 1 : Can't test it on the foss-cloud-node-01, because I have no communication with zabbix server
	# Problem 2 : I need to hard code the parameter (the vm ID), because I don't know how to get the vm ID when a virtual machine is added in the vm-manager and to the ldap.
	my $zhid = addHost("8d7e5793-798c-4836-a8ec-a7a192da76de");
	print "Zabbix Host id : $zhid \n";
	
	
	# Write the return code from the action 
	  modifyAttribute( $entry,
					   'sstProvisioningReturnValue',
					   "add",
					   $write_connection
					 );  

	  # Disconnect from the backend
	  disconnectFromServer($write_connection);

	  return $return_value;
	

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

