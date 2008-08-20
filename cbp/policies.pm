# Policy handling functions
# Copyright (C) 2008, LinuxRulz
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.


package cbp::policies;

use strict;
use warnings;

# Exporter stuff
require Exporter;
our (@ISA,@EXPORT);
@ISA = qw(Exporter);
@EXPORT = qw(
	getPolicy
	encodePolicyData
	decodePolicyData
);


use cbp::logging;
use cbp::dblayer;
use cbp::system;


# Database handle
my $dbh = undef;

# Our current error message
my $error = "";

# Set current error message
# Args: error_message
sub setError
{
	my $err = shift;
	my ($package,$filename,$line) = caller;
	my (undef,undef,undef,$subroutine) = caller(1);

	# Set error
	$error = "$subroutine($line): $err";
}

# Return current error message
# Args: none
sub Error
{
	my $err = $error;

	# Reset error
	$error = "";

	# Return error
	return $err;
}



# Return a hash of policies matches
# Returns:
# 	Hash - indexed by policy priority, the value is an array of policy ID's
sub getPolicy
{
    my ($server,$sourceIP,$emailFrom,$emailTo,$saslUsername) = @_;
	my $log = defined($server->{'config'}{'logging'}{'policies'});


	# Start with blank policy list
	my %matchedPolicies = ();


	# Grab all the policy members
	my $sth = DBSelect('
		SELECT 
			policies.Name, policies.Priority, policies.Disabled AS PolicyDisabled,
			policy_members.ID, policy_members.PolicyID, policy_members.Source, 
			policy_members.Destination, policy_members.Disabled AS MemberDisabled
		FROM
			policies, policy_members
		WHERE
			policies.Disabled = 0
			AND policy_members.Disabled = 0
			AND policy_members.PolicyID = policies.ID
	');
	if (!$sth) {
		$server->log(LOG_DEBUG,"[POLICIES] Error while selecing policy members from database: ".cbp::dblayer::Error());
		return undef;
	}
	# Loop with results
	my @policyMembers;
	while (my $row = $sth->fetchrow_hashref()) {
		# Log what we see
		if ($row->{'PolicyDisabled'} eq "1") {
			$server->log(LOG_DEBUG,"[POLICIES] Policy '".$row->{'Name'}."' is disabled") if ($log);
		} elsif ($row->{'MemberDisabled'} eq "1") {
			$server->log(LOG_DEBUG,"[POLICIES] Policy member item with ID '".$row->{'ID'}."' is disabled") if ($log);
		} else {
			$server->log(LOG_DEBUG,"[POLICIES] Found policy member with ID '".$row->{'ID'}."' in policy '".$row->{'Name'}."'") if ($log);
			push(@policyMembers,$row);
		}
	}

	# Process the Members
	foreach my $policyMember (@policyMembers) {
		# Make debugging a bit easier
		my $debugTxt = sprintf('[ID:%s/Name:%s]',$policyMember->{'ID'},$policyMember->{'Name'});

		#
		# Source Test
		#
		my $sourceMatch = 0;

		# No source or "any"
		if (!defined($policyMember->{'Source'}) || lc($policyMember->{'Source'}) eq "any") {
			$server->log(LOG_DEBUG,"[POLICIES] $debugTxt: Source not defined or 'any', explicit match: matched=1") if ($log);
			$sourceMatch = 1;

		} else {
			# Split off sources
			my @rawSources = split(/,/,$policyMember->{'Source'});
			
			$server->log(LOG_DEBUG,"[POLICIES] $debugTxt: Raw sources '".join(',',@rawSources)."'") if ($log);

			# Default to no match
			foreach my $item (@rawSources) {
				# Process item
				my $res = policySourceItemMatches($server,$debugTxt,$item,$sourceIP,$emailFrom,$saslUsername);
				# Check for error
				if ($res < 0) {
					$server->log(LOG_WARN,"[POLICIES] $debugTxt: Error while processing source item '$item', skipping...");
					$sourceMatch = 0;
					last;
				# Check for success
				} elsif ($res == 1) {
					$sourceMatch = 1;
				# Check for failure
				} else {
					$sourceMatch = 0;
					last;
				}
			}
		}
		
		$server->log(LOG_INFO,"[POLICIES] $debugTxt: Source matching result: matched=$sourceMatch");
		# Check if we passed the tests
		next if (!$sourceMatch);

		#
		# Destination Test
		#
		my $destinationMatch = 0;

		# No destination or "any"
		if (!defined($policyMember->{'Destination'}) || lc($policyMember->{'Destination'}) eq "any") {
			$server->log(LOG_DEBUG,"[POLICIES] $debugTxt: Destination not defined or 'any', explicit match: matched=1") if ($log);
			$destinationMatch = 1;
		
		} else {
			# Split off destinations
			my @rawDestinations = split(/,/,$policyMember->{'Destination'});
				
			$server->log(LOG_DEBUG,"[POLICIES] $debugTxt: Raw destinations '".join(',',@rawDestinations)."'") if ($log);

			# Parse in group data
			my @destinations;
			foreach my $item (@rawDestinations) {
				# Process item
				my $res = policyDestinationItemMatches($server,$debugTxt,$item,$emailFrom);
				# Check for error
				if ($res < 0) {
					$server->log(LOG_WARN,"[POLICIES] $debugTxt: Error while processing destination item '$item', skipping...");
					$destinationMatch = 0;
					last;
				# Check for success
				} elsif ($res == 1) {
					$destinationMatch = 1;
				# Check for failure
				} else {
					$destinationMatch = 0;
					last;
				}
			}
		}
		$server->log(LOG_INFO,"[POLICIES] $debugTxt: Destination matching result: matched=$destinationMatch") if ($log);
		# Check if we passed the tests
		next if (!$destinationMatch);

		push(@{$matchedPolicies{$policyMember->{'Priority'}}},$policyMember->{'PolicyID'});
	}

	# If we logging, display a list
	if ($log) {
		foreach my $prio (sort keys %matchedPolicies) {
			$server->log(LOG_DEBUG,"[POLICIES] END RESULT: prio=$prio - policy_list=".join(',',@{$matchedPolicies{$prio}}));
		}
	}

	return \%matchedPolicies;
}



# Get group members from group name
sub getGroupMembers
{
	my $group = shift;


	# Grab group members
	my $sth = DBSelect("
		SELECT 
			policy_group_members.Member
		FROM
			policy_groups, policy_group_members
		WHERE
			policy_groups.Name = ".DBQuote($group)."
			AND policy_groups.ID = policy_group_members.PolicyGroupID
			AND policy_groups.Disabled = 0
			AND policy_group_members.Disabled = 0
	");
	if (!$sth) {
		return cbp::dblayer::Error();
	}
	# Pull in groups
	my @groupMembers = ();
	while (my $row = $sth->fetchrow_hashref()) {
		push(@groupMembers,$row);
	}

	# Loop with results
	my @res;
	foreach my $item (@groupMembers) {
		push(@res,$item->{'Member'});
	}

	return \@res;
}


# Check if this source item matches, this function automagically resolves groups aswell
sub policySourceItemMatches
{
    my ($server,$debugTxt,$rawItem,$sourceIP,$emailFrom,$saslUsername) = @_;
	my $log = defined($server->{'config'}{'logging'}{'policies'});


	# Rip out negate if we have it, and clean the item
	my ($negate,$tmpItem) = ($rawItem =~ /^(!)?(.*)/);
	# See if we match %, if we do its a group
	my ($isGroup,$item) = ($tmpItem =~ /^(%)?(.*)/);
	
	# Check if this is a group
	my $match = 0;
	if ($isGroup) {
		# Get group members
		my $groupMembers = getGroupMembers($item);
		if (ref $groupMembers ne "ARRAY") {
			$server->log(LOG_WARN,"[POLICIES] $debugTxt: Error '$groupMembers' while retrieving group members for source group '$item'");
			return -1;
		}
		# Check if actually have any
		if (@{$groupMembers} > 0) {
			foreach my $gmember (@{$groupMembers}) {
				# Process this group member
				my $res = policySourceItemMatches($server,"$debugTxt=>(group:$item)",$gmember,$sourceIP,$emailFrom,$saslUsername);
				# Check for match
				if ($res) {
					$match = 1;
					last;
				# Check for hard error
				} elsif ($res < 0) {
					return $res;
				}
			}
		} else {
			$server->log(LOG_WARN,"[POLICIES] $debugTxt: No group members for source group '$item'");
		}

	# Normal member
	} else {
		my $res = 0;

		# Match IP
		if ($item =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(?:\/\d{1,2})$/) {
			$res = ipMatches($sourceIP,$item);
			$server->log(LOG_DEBUG,"[POLICIES] $debugTxt: - Resolved source '$item' to a IP/CIDR specification, match = $res") if ($log);

		# Match SASL user, must be above email addy to match SASL usernames in the same format as email addies
		} elsif ($item =~ /^\$\S+$/) {
			$res = saslUsernameMatches($saslUsername,$item);
			$server->log(LOG_DEBUG,"[POLICIES] $debugTxt: - Resolved source '$item' to a SASL user specification, match = $res") if ($log);

		# Match email addy
		} elsif ($item =~ /^\S*@\S+$/) {
			$res = emailAddressMatches($emailFrom,$item);
			$server->log(LOG_DEBUG,"[POLICIES] $debugTxt: - Resolved source '$item' to a email address specification, match = $res") if ($log);

		# Not valid
		} else {
			$server->log(LOG_WARN,"[POLICIES] $debugTxt: - Source '".$item."' is not a valid specification");
		}
		
		$match = 1 if ($res);
	}

	# Check the result, if its undefined or 0, return 0, if its 1 return 1
	# !1 == undef
	return ($negate ? !$match : $match) ? 1 : 0;
}



# Check if this destination item matches, this function automagically resolves groups aswell
sub policyDestinationItemMatches
{
    my ($server,$debugTxt,$rawItem,$emailTo) = @_;
	my $log = defined($server->{'config'}{'logging'}{'policies'});


	# Rip out negate if we have it, and clean the item
	my ($negate,$tmpItem) = ($rawItem =~ /^(!)?(.*)/);
	# See if we match %, if we do its a group
	my ($isGroup,$item) = ($tmpItem =~ /^(%)?(.*)/);
	
	# Check if this is a group
	my $match = 0;
	if ($isGroup) {
		# Get group members
		my $groupMembers = getGroupMembers($item);
		if (ref $groupMembers ne "ARRAY") {
			$server->log(LOG_WARN,"[POLICIES] $debugTxt: Error '$groupMembers' while retrieving group members for destination group '$item'");
			return -1;
		}
		# Check if actually have any
		if (@{$groupMembers} > 0) {
			foreach my $gmember (@{$groupMembers}) {
				# Process this group member
				my $res = policyDestinationItemMatches($server,"$debugTxt=>(group:$item)",$gmember,$emailTo);
				# Check for match
				if ($res) {
					$match = 1;
					last;
				# Check for hard error
				} elsif ($res < 0) {
					return $res;
				}
			}
		} else {
			$server->log(LOG_WARN,"[POLICIES] $debugTxt: No group members for destination group '$item'");
		}

	# Normal member
	} else {
		my $res = 0;

		# Match email addy
		if ($item =~ /^!?\S*@\S+$/) {
			$res = emailAddressMatches($emailTo,$item);
			$server->log(LOG_DEBUG,"[POLICIES] $debugTxt: - Resolved destination '$item' to a email address specification, match = $res") if ($log);

		} else {
			$server->log(LOG_WARN,"[POLICIES] $debugTxt: - Destination '$item' is not a valid specification");
		}
		
		$match = 1 if ($res);
	}

	# Check the result, if its undefined or 0, return 0, if its 1 return 1
	# !1 == undef
	return ($negate ? !$match : $match) ? 1 : 0;
}



# Check if first arg falls within second arg CIDR
sub ipMatches
{
	my ($ip,$cidr) = @_;


	# Pull off parts of IP
	my ($cidr_address,$cidr_mask) = ($cidr =~ /^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})(?:\/(\d{1,2}))$/);

	# Pull long for IP we going to test
	my $ip_long = ip_to_long($ip);

	# Convert CIDR to longs
	my $cidr_address_long = ip_to_long($cidr_address);
	my $cidr_mask_long = bits_to_mask($cidr_mask ? $cidr_mask : 32);
	# Pull out network address
	my $cidr_network_long = $cidr_address_long & $cidr_mask_long;
	# And broadcast
	my $cidr_broadcast_long = $cidr_address_long | (IPMASK ^ $cidr_mask_long);

	# Convert to quad;/
	my $cidr_network = long_to_ip($cidr_network_long);
	my $cidr_broadcast = long_to_ip($cidr_broadcast_long);

	# Default to no match
	my $match = 0;

	# Check IP is within range
	if ($ip_long >= $cidr_network_long && $ip_long <= $cidr_broadcast_long) {
		$match = 1;
	}

	return $match;
}


# Check if first arg lies within the scope of second arg email/domain
sub emailAddressMatches
{
	my ($email,$template) = @_;

	my $match = 0;

	# Strip email addy
	my ($email_user,$email_domain) = ($email =~ /^(\S+)@(\S+)$/);
	my ($template_user,$template_domain) = ($template =~ /^(\S*)@(\S+)$/);

	if (lc($email_domain) eq lc($template_domain) && (lc($email_user) eq lc($template_user) || $template_user eq "")) {
		$match = 1;
	}

	return $match;
}


# Check if first arg lies within the scope of second arg sasl specification
sub saslUsernameMatches
{
	my ($saslUsername,$template) = @_;

	my $match = 0;

	# Decipher template
	my ($template_user) = ($template =~ /^\$(\S+)$/);

	# $- is a special case which allows matching against no SASL username
	if ($template_user eq '-' && !$saslUsername) {
		$match = 1;
	# Else normal match
	} elsif (lc($saslUsername) eq lc($template_user) || $template_user eq "*") {
		$match = 1;
	}

	return $match;
}


# Encode policy data into session recipient data
sub encodePolicyData
{
	my ($email,$policy) = @_;

	# Generate...    <recipient@domain>#priority=policy_id,policy_id,policy_id;priority2=policy_id2,policy_id2/recipient2@...
	my $ret = "<$email>#";
	foreach my $priority (keys %{$policy}) {
		$ret .= sprintf('%s=%s;',$priority,join(',',@{$policy->{$priority}}));
	}

	return $ret;
}


# Decode recipient data into policy data
sub decodePolicyData
{
	my $recipientData = shift;


	my %recipientToPolicy;
	# Build policy str list and recipients list
	foreach my $item (split(/\//,$recipientData)) {
		# Skip over first /
		next if ($item eq "");

		my ($email,$rawPolicy) = ($item =~ /<([^>]*)>#(.*)/);
		
		# Loop with raw policies
		foreach my $policy (split(/;/,$rawPolicy)) {
			# Strip off priority and policy IDs
			my ($prio,$policyIDs) = ( $policy =~ /(\d+)=(.*)/ );
			# Pull off policyID's from string
			foreach my $pid (split(/,/,$policyIDs)) {
				push(@{$recipientToPolicy{$email}{$prio}},$pid);
			}
		}
	}

	return \%recipientToPolicy;
}


1;
# vim: ts=4
