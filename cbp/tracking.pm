# Message tracking functions
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


package cbp::tracking;

use strict;
use warnings;

# Exporter stuff
require Exporter;
our (@ISA,@EXPORT,@EXPORT_OK);
@ISA = qw(Exporter);
@EXPORT = qw(
	updateSessionData
	getSessionDataFromRequest
	getSessionDataFromQueueID
);


use cbp::dblayer;
use cbp::logging;
use cbp::policies;
use cbp::system qw(parseCIDR);

use Data::Dumper;


# Database handle
my $dbh = undef;

# Get session data from mail_id
sub getSessionDataFromQueueID
{
	my ($server,$queueID,$clientAddress,$sender) = @_;

	$server->log(LOG_DEBUG,"[TRACKING] Retreiving session data for triplet: $queueID/$clientAddress/$sender");
	
	# Pull in session data
	my $sth = DBSelect("
		SELECT
			Instance, QueueID,
			Timestamp,
			ClientAddress, ClientName, ClientReverseName,
			Protocol,
			EncryptionProtocol, EncryptionCipher, EncryptionKeySize,
			SASLMethod, SASLSender, SASLUsername,
			Helo,
			Sender,
			Size,
			RecipientData
		FROM
			session_tracking
		WHERE
			QueueID = ".DBQuote($queueID)."
			AND ClientAddress = ".DBQuote($clientAddress)."
			AND Sender = ".DBQuote($sender)."
	");
	if (!$sth) {
		$server->log(LOG_ERR,"[TRACKING] Failed to select session tracking info: ".cbp::dblayer::Error());
		return -1;
	}
	my $sessionData = $sth->fetchrow_hashref();
	
	if (!$sessionData) {
		$server->log(LOG_ERR,"[TRACKING] No session data");
		return -1;
	}

	# Pull in decoded policy
	$sessionData->{'_Recipient_To_Policy'} = decodePolicyData($sessionData->{'RecipientData'});

	return $sessionData;
}


# Get session data
# Params:
# 	server, request
sub getSessionDataFromRequest
{
	my ($server,$request) = @_;
	my $log = defined($server->{'config'}{'logging'}{'tracking'});


	# We must have protocol transport
	if (!defined($request->{'_protocol_transport'})) {
		$server->log(LOG_ERR,"[TRACKING] No protocol transport specified");
		return -1;
	}

	my $sessionData;

	# Check protocol
	if ($request->{'_protocol_transport'} eq "Postfix") {
		my $initSessionData = 0;

		# Check if we need to track the sessions...
		if ($server->{'config'}->{'track_sessions'}) {

			# Pull in session data
			my $sth = DBSelect("
				SELECT
					Instance, QueueID,
					Timestamp,
					ClientAddress, ClientName, ClientReverseName,
					Protocol,
					EncryptionProtocol, EncryptionCipher, EncryptionKeySize,
					SASLMethod, SASLSender, SASLUsername,
					Helo,
					Sender,
					Size,
					RecipientData
				FROM
					session_tracking
				WHERE
					Instance = ".DBQuote($request->{'instance'})."
			");
			if (!$sth) {
				$server->log(LOG_ERR,"[TRACKING] Failed to select session tracking info: ".cbp::dblayer::Error());
				return -1;
			}
			$sessionData = $sth->fetchrow_hashref();
				
			# If no state information, create everything we need
			if (!$sessionData) {

				$server->log(LOG_DEBUG,"[TRACKING] No session tracking data exists for request: ".Dumper($request)) if ($log);

				# Should only track sessions from RCPT
				if ($request->{'protocol_state'} eq "RCPT") {
					DBBegin();
	
					# Record tracking info
					$sth = DBDo("
						INSERT INTO session_tracking 
							(
								Instance,QueueID,
								Timestamp,
								ClientAddress, ClientName, ClientReverseName,
								Protocol,
								EncryptionProtocol,EncryptionCipher,EncryptionKeySize,
								SASLMethod,SASLSender,SASLUsername,
								Helo,
								Sender,
								Size
							)
						VALUES
							(
								".DBQuote($request->{'instance'}).", ".DBQuote($request->{'queue_id'}).",
								".DBQuote($request->{'_timestamp'}).",
								".DBQuote($request->{'client_address'}).", ".DBQuote($request->{'client_name'}).", 
								".DBQuote($request->{'reverse_client_name'}).",
								".DBQuote($request->{'protocol_name'}).",
								".DBQuote($request->{'encryption_protocol'}).", ".DBQuote($request->{'encryption_cipher'}).", 
								".DBQuote($request->{'encryption_keysize'}).",
								".DBQuote($request->{'sasl_method'}).", ".DBQuote($request->{'sasl_sender'}).",
										".DBQuote($request->{'sasl_username'}).",
								".DBQuote($request->{'helo_name'}).",
								".DBQuote($request->{'sender'}).",
								".DBQuote($request->{'size'})."
							)
					");
					if (!$sth) {
						$server->log(LOG_ERR,"[TRACKING] Failed to record session tracking info: ".cbp::dblayer::Error());
						DBRollback();
						return -1;
					}
					$server->log(LOG_DEBUG,"[TRACKING] Added session tracking information for: ".Dumper($request)) if ($log);
	
					DBCommit();

					# Initialize session data later on, we didn't get anything from the DB
					$initSessionData = 1;
				}
			}
		}

		# Check if we must initialize the session data from the request
		if ($initSessionData) {	
			$sessionData->{'Instance'} = $request->{'instance'};
			$sessionData->{'QueueID'} = $request->{'queue_id'};
			$sessionData->{'ClientAddress'} = $request->{'client_address'};
			$sessionData->{'ClientName'} = $request->{'client_name'};
			$sessionData->{'ClientReverseName'} = $request->{'reverse_client_name'};
			$sessionData->{'Protocol'} = $request->{'protocol_name'};
			$sessionData->{'EncryptionProtocol'} = $request->{'encryption_protocol'};
			$sessionData->{'EncryptionCipher'} = $request->{'encryption_cipher'};
			$sessionData->{'EncryptionKeySize'} = $request->{'encryption_keysize'};
			$sessionData->{'SASLMethod'} = $request->{'sasl_method'};
			$sessionData->{'SASLSender'} = $request->{'sasl_sender'};
			$sessionData->{'SASLUsername'} = $request->{'sasl_username'};
			$sessionData->{'Helo'} = $request->{'helo_name'};
			$sessionData->{'Sender'} = $request->{'sender'};
			$sessionData->{'Size'} = $request->{'size'};
			$sessionData->{'RecipientData'} = "";
		}

		# If we in rcpt, caclulate and save policy
		if ($request->{'protocol_state'} eq 'RCPT') {
			$server->log(LOG_DEBUG,"[TRACKING] Protocol state is 'RCPT', resolving policy...") if ($log);

			$sessionData->{'Recipient'} = $request->{'recipient'};

			# Get policy
			my $policy = getPolicy($server,$sessionData);
			if (ref $policy ne "HASH") {
				return -1;
			}
			
			$server->log(LOG_DEBUG,"[TRACKING] Policy resolved into: ".Dumper($policy)) if ($log);
	
			$sessionData->{'Policy'} = $policy;
	
		# If we in end of message, load policy from data
		} elsif ($request->{'protocol_state'} eq 'END-OF-MESSAGE') {
			$server->log(LOG_DEBUG,"[TRACKING] Protocol state is 'END-OF-MESSAGE', decoding policy...") if ($log);
			# Decode... only if we actually have session data from the DB, which means initSessionData is 0
			if (!$initSessionData) {
				$sessionData->{'_Recipient_To_Policy'} = decodePolicyData($sessionData->{'RecipientData'});
			}
			
			$server->log(LOG_DEBUG,"[TRACKING] Decoded into: ".Dumper($sessionData->{'_Recipient_To_Policy'})) if ($log);

			# This must be updated here ... we may of got actual size
			$sessionData->{'Size'} = $request->{'size'};
			# Only get a queue id once we have gotten the message
			$sessionData->{'QueueID'} = $request->{'queue_id'};
		}

	# Check for HTTP protocol transport
	} elsif ($request->{'_protocol_transport'} eq "HTTP") {
		$sessionData->{'ClientAddress'} = $request->{'client_address'};
		$sessionData->{'ClientReverseName'} = $request->{'client_reverse_name'} if (defined($request->{'client_reverse_name'}));
		$sessionData->{'Helo'} = $request->{'helo_name'} if (defined($request->{'helo_name'}));
		$sessionData->{'Sender'} = $request->{'sender'};

		# If we in RCPT state, set recipient
		if ($request->{'protocol_state'} eq "RCPT") {
			$server->log(LOG_DEBUG,"[TRACKING] Protocol state is 'RCPT', resolving policy...") if ($log);

			# Get policy
			my $policy = getPolicy($server,$request->{'client_address'},$request->{'sender'},$request->{'recipient'},$request->{'sasl_username'});
			if (ref $policy ne "HASH") {
				return -1;
			}
			
			$server->log(LOG_DEBUG,"[TRACKING] Policy resolved into: ".Dumper($policy)) if ($log);
	
			$sessionData->{'Policy'} = $policy;
			$sessionData->{'Recipient'} = $request->{'recipient'};
		}
	}

	# Shove in various thing not stored in DB
	$sessionData->{'ProtocolTransport'} = $request->{'_protocol_transport'};
	$sessionData->{'ProtocolState'} = $request->{'protocol_state'};
	$sessionData->{'Timestamp'} = $request->{'_timestamp'};
	$sessionData->{'ParsedClientAddress'} = parseCIDR($sessionData->{'ClientAddress'});

	# Make sure HELO is clean...
	$sessionData->{'Helo'} = defined($sessionData->{'Helo'}) ? $sessionData->{'Helo'} : '';

	$server->log(LOG_DEBUG,"[TRACKING] Request translated into session data: ".Dumper($sessionData)) if ($log);

	return $sessionData;
}


# Record session data
# Args:
# 	$server, $sessiondata
sub updateSessionData
{
	my ($server,$sessionData) = @_;


	# Check the protocol transport
	if ($sessionData->{'ProtocolTransport'} eq "Postfix") {

		# Return if we're not in RCPT state, in this case we shouldn't update the data
		if ($sessionData->{'ProtocolState'} eq 'RCPT') {
	
			# Get encoded policy data
			my $policyData = encodePolicyData($sessionData->{'Recipient'},$sessionData->{'Policy'});
			# Make sure recipient data is set
			my $recipientData = defined($sessionData->{'RecipientData'}) ? $sessionData->{'RecipientData'} : "";
			# Generate recipient data, make sure we don't use a undefined value either!
			$recipientData .= "/$policyData";
	
			# Record tracking info
			my $sth = DBDo("
				UPDATE 
					session_tracking 
				SET
					RecipientData = ".DBQuote($recipientData)." 
				WHERE
					Instance = ".DBQuote($sessionData->{'Instance'})."
			");
			if (!$sth) {
				$server->log(LOG_ERR,"[TRACKING] Failed to update recipient data in session tracking info: ".cbp::dblayer::Error());
				return -1;
			}
		
		# If we at END-OF-MESSAGE, update size
		} elsif ($sessionData->{'ProtocolState'} eq 'END-OF-MESSAGE') {
			# Record tracking info
			my $sth = DBDo("
				UPDATE 
					session_tracking 
				SET
					QueueID = ".DBQuote($sessionData->{'QueueID'})." ,
					Size = ".DBQuote($sessionData->{'Size'})." 
				WHERE
					Instance = ".DBQuote($sessionData->{'Instance'})."
			");
			if (!$sth) {
				$server->log(LOG_ERR,"[TRACKING] Failed to update size in session tracking info: ".cbp::dblayer::Error());
				return -1;
			}
		}
	}

	return 0;
}

1;
# vim: ts=4
