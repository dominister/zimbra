<?php
# Module: CheckSPF change
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



include_once("includes/header.php");
include_once("includes/footer.php");
include_once("includes/db.php");



$db = connect_db();



printHeader(array(
		"Tabs" => array(
			"Back to SPF checks" => "checkspf-main.php"
		),
));



# Display change screen
if ($_POST['action'] == "change") {

	# Check a SPF check was selected
	if (isset($_POST['checkspf_id'])) {
		# Prepare statement
		$stmt = $db->prepare('
			SELECT 
				checkspf.ID, checkspf.PolicyID, checkspf.Name, checkspf.UseSPF, checkspf.RejectFailedSPF, checkspf.AddSPFHeader,
				checkspf.Comment, checkspf.Disabled,
				
				policies.Name AS PolicyName
				
			FROM 
				checkspf, policies 

			WHERE 
				checkspf.ID = ?
				AND policies.ID = checkspf.PolicyID
			');
?>
		<h1>Update SPF Check</h1>

		<form action="checkspf-change.php" method="post">
			<div>
				<input type="hidden" name="action" value="change2" />
				<input type="hidden" name="checkspf_id" value="<?php echo $_POST['checkspf_id']; ?>" />
			</div>
<?php

			$res = $stmt->execute(array($_POST['checkspf_id']));

			$row = $stmt->fetchObject();
?>
			<table class="entry" style="width: 75%;">
				<tr>
					<td></td>
					<td class="entrytitle textcenter">Old Value</td>
					<td class="entrytitle textcenter">New Value</td>
				</tr>
				<tr>
					<td class="entrytitle">Name</td>
					<td class="oldval"><?php echo $row->name ?></td>
					<td><input type="text" name="checkspf_name" /></td>
				</tr>
				<tr>
					<td class="entrytitle">Link to policy</td>
					<td class="oldval"><?php echo $row->policyname ?></td>
					<td>
						<select name="checkspf_policyid">
							<option value="">--</option>
<?php
							$res = $db->query("SELECT ID, Name FROM policies ORDER BY Name");
							while ($row2 = $res->fetchObject()) {
?>
								<option value="<?php echo $row2->id ?>" ><?php echo $row2->name ?></option>
<?php
							}
?>
						</select>
					</td>
				</tr>
				<tr>
					<td class="entrytitle">Use SPF</td>
					<td class="oldval"><?php 
							switch ($row->usespf) {
								case null:
									echo "Inherit";
									break;
								case 1:
									echo "Yes";
									break;
								case 2:
									echo "No";
									break;
								default:
									echo "UNKNOWN";
									break;
							}
					?></td>
					<td>
						<select name="checkspf_usespf">
							<option value="">--</option>
							<option value="1">Inherit</option>
							<option value="2">Yes</option>
							<option value="3">No</option>
						</select>
					</td>
				</tr>
				<tr>
					<td class="entrytitle">Reject Failed SPF</td>
					<td class="oldval"><?php 
							switch ($row->rejectfailedspf) {
								case null:
									echo "Inherit";
									break;
								case 1:
									echo "Yes";
									break;
								case 2:
									echo "No";
									break;
								default:
									echo "UNKNOWN";
									break;
							}
					?></td>
					<td>
						<select name="checkspf_rejectfailed">
							<option value="">--</option>
							<option value="1">Inherit</option>
							<option value="2">Yes</option>
							<option value="3">No</option>
						</select>
					</td>
				</tr>
				<tr>
					<td class="entrytitle">Add SPF Header</td>
					<td class="oldval"><?php 
							switch ($row->addspfheader) {
								case null:
									echo "Inherit";
									break;
								case 1:
									echo "Yes";
									break;
								case 2:
									echo "No";
									break;
								default:
									echo "UNKNOWN";
									break;
							}
					?></td>
					<td>
						<select name="checkspf_addheader">
							<option value="">--</option>
							<option value="1">Inherit</option>
							<option value="2">Yes</option>
							<option value="3">No</option>
						</select>
					</td>
				</tr>
				<tr>
					<td class="entrytitle texttop">Comment</td>
					<td class="oldval texttop"><?php echo $row->comment ?></td>
					<td><textarea name="checkspf_comment" cols="40" rows="5"></textarea></td>
				</tr>
				<tr>
					<td class="entrytitle">Disabled</td>
					<td class="oldval"><?php echo $row->disabled ? 'yes' : 'no' ?></td>
					<td>
						<select name="checkspf_disabled">
							<option value="">--</option>
							<option value="0">No</option>
							<option value="1">Yes</option>
						</select>		
					</td>
				</tr>
			</table>
	
			<p />
			<div class="textcenter">
				<input type="submit" />
			</div>
		</form>
<?php
	} else {
?>
		<div class="warning">No access control selected</div>
<?php
	}
	
	
	
# SQL Updates
} elseif ($_POST['action'] == "change2") {
?>
	<h1>SPF Check Update Results</h1>
<?
	$updates = array();

	if (!empty($_POST['checkspf_policyid'])) {
		array_push($updates,"PolicyID = ".$db->quote($_POST['checkspf_policyid']));
	}
	if (!empty($_POST['checkspf_name'])) {
		array_push($updates,"Name = ".$db->quote($_POST['checkspf_name']));
	}
	if (!empty($_POST['checkspf_usespf'])) {
		if ($_POST['checkspf_usespf'] == "1") {
			$usespf = null;
		} elseif ($_POST['checkspf_usespf'] == "2") {
			$usespf = 1;
		} elseif ($_POST['checkspf_usespf'] == "3") {
			$usespf = 0;
		}
		array_push($updates,"UseSPF = ".$db->quote($usespf));
	}
	if (!empty($_POST['checkspf_rejectfailed'])) {
		if ($_POST['checkspf_rejectfailed'] == "1") {
			$rejectfailed = null;
		} elseif ($_POST['checkspf_rejectfailed'] == "2") {
			$rejectfailed = 1;
		} elseif ($_POST['checkspf_rejectfailed'] == "3") {
			$rejectfailed = 0;
		}
		array_push($updates,"RejectFailedSPF = ".$db->quote($rejectfailed));
	}
	if (!empty($_POST['checkspf_addheader'])) {
		if ($_POST['checkspf_addheader'] == "1") {
			$addheader = null;
		} elseif ($_POST['checkspf_addheader'] == "2") {
			$addheader = 1;
		} elseif ($_POST['checkspf_addheader'] == "3") {
			$addheader = 0;
		}
		array_push($updates,"AddSPFHeader = ".$db->quote($addheader));
	}
	if (!empty($_POST['checkspf_comment'])) {
		array_push($updates,"Comment = ".$db->quote($_POST['checkspf_comment']));
	}
	if (isset($_POST['checkspf_disabled']) && $_POST['checkspf_disabled'] != "") {
		array_push($updates ,"Disabled = ".$db->quote($_POST['checkspf_disabled']));
	}

	# Check if we have updates
	if (sizeof($updates) > 0) {
		$updateStr = implode(', ',$updates);

		$res = $db->exec("UPDATE checkspf SET $updateStr WHERE ID = ".$db->quote($_POST['checkspf_id']));
		if ($res) {
?>
			<div class="notice">SPF check updated</div>
<?php
		} else {
?>
			<div class="warning">Error updating SPF check!</div>
			<div class="warning"><?php print_r($db->errorInfo()) ?></div>
<?php
		}

	} else {
?>
		<div class="warning">No changes made to SPF check</div>
<?php
	}

} else {
?>
	<div class="warning">Invalid invocation</div>
<?php
}


printFooter();


# vim: ts=4
?>
