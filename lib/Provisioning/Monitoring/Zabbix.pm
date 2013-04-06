package Provisioning::Monitoring::Zabbix;

# Copyright (C) 2012 FOSS-Group
#                    Germany
#                    http://www.foss-group.de
#                    support@foss-group.de
#
# Authors:
#  Name Surname <stijn.van.paesschen@student.groept.be>
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

use Provisioning::Log;

use Provisioning::Backend::LDAP;

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

	my $customer_uid = getValue( $entry, "sstBelongsToCustomerUID");
	my $subtree = "ou=customers,dc=foss-cloud,dc=org";
	my $filter = "(uid=$customer_uid)";
	
	my @results = simpleSearch( $subtree, $filter, "sub");
	
	if ( @results != 1 )
	{
		print "Too much results \n";
	} else {
		my $customer_name = getValue($results[0], "o");
		print "Customer name is $customer_name \n";
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


1;

__END__
