#!/bin/bash
clear
testDate=$(date +"%d-%m-%Y|%T")

function timer {

timeStamp=$(date) 
timerDay="$(echo $timeStamp | awk '{ print $2 }')"
timerMonth="$(echo $timeStamp | awk '{ print $3 }')"
timerTime="$(echo $timeStamp | awk '{ print $4 }')"
echo -e "\n----- NEW TEST STARTED: -----"
echo $timerDay
echo $timerMonth
echo $timerTime
echo -e "--------------------"

}

# Function will call the edit SimBox expect script (<DeskID> <Router num> <Add/Remove> <NumOfGigE> <BoxHID> <GigEPort> <isMasterRouter> <isSampleRate>)
function editSimBoxes {	#000000
	/usr/bin/expect -f .sys/editSimBoxes.exp $1 $2 $3 $4 $5 $6 $7 $8 >> /dev/null
}

# Function will call the routerReset expect script (<DeskID> <Router num> <reset method> <isMasterRouter>)
function routerFailure {
	/usr/bin/expect -f .sys/routerResets.exp $1 $2 $3 $4 >> /dev/null
	# >> .dump/_DUMPFILE_routerFailure.txt
}
  
function gatherLogs {
	echo -e "-----INSIDE GATHERLOGS-----\n"
	gatherDate=$(date +"%d-%m-%Y|%T")
	/usr/bin/expect -f .validationScripts/gatherLog.exp $1 $2 $3
	sshpass -pM0ntana scp -r root@54.18.1.0:/root/lightsOUT_log_gather logs/$gatherDate-$2.$3
	sshpass -pM0ntana ssh root@54.18.1.0 rm -r -f /root/lightsOUT_log_gather
	echo -e "\n-----EXITING GATHERLOGS-----\n"
}

# Function will call the Master Router Ping expect script
function mrPing {
	/usr/bin/expect -f .sys/mrPing.exp $1 | grep PING
}

function callSPC {
	/usr/bin/expect -f .validationScripts/callSPC.exp $1 | grep PatchStore
}

# This function is for testing w/o network only
function catSPC {
	shouldFlood=$1
	cat /run/media/tommysutton/TJS\ Calrec/H2Router.log | grep "PatchStore Patch Count"
}

function validateSPC { 
	isPatchCount=4096
	isPendingPatches=0
	Counter=0

	patchFile=$(callSPC $1)																			# Change function from "catSPC" to "callSPC"
	patchNum=$((`echo $patchFile | awk '{ print $8 }' | tr -d '[[:space:]]'`))			# token 7 = patchStore number. Remove white space and special characters. Store as int
	anyPending=$((`echo $patchFile | awk '{ print $10 }' | tr -d '[[:space:]]'`))			# token 10 = pending patches number. Remove white space and special characters. Store as int

	#declare -i anyPending
	echo -e "--- PatchCount:  " $patchNum	
	echo -e "--- Pending:     " $anyPending
	echo -e " "

	# Return "0" if patchCount is NOT EQUAL to "$isPatchCount" variable
	if [ "$patchNum" != "$isPatchCount" ] || [ "$anyPending" != "$isPendingPatches" ]
	then
		return 0
	else
		return 1
	fi
}

# Declare variables || import system config from text files
deskIDs=($(<.sys/conf/deskIDList.txt))	
rackTypes=($(<.sys/conf/deskPackList.txt))						
rackLevels=($(<.sys/conf/deskLevelList.txt))				

echo -e "\n----------Enter lightsOUT main--------------------------------------------------------------------------------------------------\n"

optionList=("List Automated Tests" "Configure test system" "Populate Core IO" "Display current patch count" "Quit")								# Menu List
select opt in "${optionList[@]}"
do
	case $opt in
		"List Automated Tests")
			echo -e ""
				testList=("IO redundancy" "Router redundancy" "AutoPromotion")
				select testOpt in "${testList[@]}"
				do
					case $testOpt in
						"IO redundancy")
						echo -e "Test started at: " 
						date

						echo -e "Please enter the <day> <month> <time> to stop the test"
						echo -e "day (e.g 11)"
						read usrTimerDay
						echo -e "month (e.g "Nov")"
						read usrTimerMonth
						echo $usrTimerDay
						echo $usrTimerMonth
						timer
						
						echo -e "Set sleep duration (s) (Time between link events + checks)"
						read sampleRateSleep		

						echo -e "Are the tests running @ 48kHz or 96kHz?"
						read isSampleRate			
						
						while [ $usrTimerDay -ne $timerDay ]
						do
						
							for a in ${deskIDs[@]}	# use "@" to do all racks
							do
							
###########################################################################################
#							  Work out if the intended core is MR. If not "editSimBoxes" script	#
#							  will need to tunnel through MR router card for telnet to r:core	   #
###########################################################################################
							
								coreIoInfo=($(<.sys/conf/coreHIDs/$a.IOsetup))																									# Import text file containing HID numbers for current rack		
								echo ${coreIoInfo[@]}
								echo -e "\n#"
								echo -e "#"
								echo -e "# Processing rack" $a "------------------------------------------------"

								if [ $a != "54.18" ]																																				# If "$coreToPopulate != "0" (MR) then "editSimBoxes" will 
								then																																									# need to ssh into MR then into slave router to build IO
									echo -e "# CORE IS NOT MASTER ROUTER"
									isMasterRouter=0																																			# Set flag if router IS NOT MR
								else
									echo -e "#"
									isMasterRouter=1																																			# Set flag if router IS MR
								fi								
								echo -e "#"	

								gigeCount=0
								
###########################################################################################
#							  Use "editSimBoxes" function to remove/add primary + secondary IO	#
#							  links > SimBoxes calling the "validateSPC" function after each test#
###########################################################################################					
								
								for IO in ${coreIoInfo[@]}
								do
									echo -e "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ HID $IO Primary Link\n"
									editSimBoxes $a 5 remove 0 $IO $gigeCount $isMasterRouter	# Remove HID primary
									echo -e "Removed PRI link for HID:" $IO
									echo -e "----------------------------"
									sleep 3
									echo -e "\nPrimary patchstore:"
									sleep 2 
									validateSPC 5
									echo -e "Secondary patchstore:"
									sleep 2 
									validateSPC 6
									sleep 2
									
									editSimBoxes $a 5 add 0 $IO $gigeCount $isMasterRouter $isSampleRate														# Re-add HID primary
									echo -e "Added PRI link for HID:" $IO																												# Add check for !!pending!! as there should be NONE here
									echo -e "--------------------------"
									sleep 3
									echo -e "\nPrimary patchstore:"
									sleep $sampleRateSleep
									
###########################################################################################
#							  Call "ValidateSPC" function to retrieve and display current spc,									 #
#							  the output is compared to a variable set in function. return 1/0										 #
###########################################################################################										
									
									validateSPC 5
									if [ $? != 1 ]
									then
										echo -e "------------------------ Test has FAILED\n"
										date=$(date)
										echo -e "$date \npatchCount error when re-inserting primary link \nHID: $IO \nRouter: $a.5.0\n" >> logs/FAIL:$a.log
										gatherLogs $isMasterRouter $a 5
										# Gather local and MR log here
										editSimBoxes $a 5 add 0 $IO $gigeCount $isMasterRouter																			# Re-add HID primary
									else
										echo -e "------------------------ Test has PASSED\n"
									fi
									sleep 1					
									echo -e "Secondary patchstore:"
									sleep 2 
									validateSPC 6

###########################################################################################
#							  Repeat process for the secondary IO link, validateSPC is performed #
#							  after the secondary link is re-inserted										#
###########################################################################################

									echo -e "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ HID $IO Seconary Link\n"
									editSimBoxes $a 6 remove 0 $IO $gigeCount $isMasterRouter																			# Remove HID secondary
									echo -e "Removed SEC link for HID:" $IO
									echo -e "----------------------------"
									sleep 3
									echo -e "\nPrimary patchstore:"
									sleep 2 
									validateSPC 5
									echo -e "Secondary patchstore:"
									sleep 2 
									validateSPC 6
									sleep 2
																		
									editSimBoxes $a 6 add 0 $IO $gigeCount $isMasterRouter $isSampleRate														# re-add HID secondary
									echo -e "\nAdded SEC link for HID:" $IO																											# Add check for !!pending!! as there should be NONE here
									echo -e "--------------------------"
									sleep 3
									echo -e "\nPrimary patchstore:"
									sleep 3 
									validateSPC 5
									echo -e "Secondary patchstore:"
									sleep $sampleRateSleep	 
									validateSPC 6
									if [ $? != 1 ]
									then
										echo -e "------------------------ Test has FAILED\n" 
										date=$(date)
										echo -e "$date \npatchCount error when re-inserting secondary link \nHID: $IO \nRouter: $a.6.0\n" >> logs/FAIL:$a.log
										gatherLogs $isMasterRouter $a 6				
										# Gather local and MR log here
										editSimBoxes $a 6 add 0 $IO $gigeCount $isMasterRouter $isSampleRarte													# re-add HID secondary
									else
										echo -e "------------------------ Test has PASSED\n"
									fi
									
									sleep 1									

									((gigeCount++))					
								done
								echo -e "Test finished at: "
								date
								timer
							done
							done
							break
							;; 
					"Router redundancy")
						resetMethod="stopkicking" 
					
						for a in ${deskIDs[@]}	# use "@" to do all racks
						do
							coreIoInfo=($(<.sys/conf/coreHIDs/$a.IOsetup))	
							echo -e "\n#"
							echo -e "#"
							echo -e "# Processing rack" $a "------------------------------------------------"
							
							if [ $a != "54.18" ]																																					# If "$coreToPopulate != "0" (MR) then "editSimBoxes" will 
							then																																										# need to ssh into MR then into slave router to build IO
								echo -e "# CORE IS NOT MASTER ROUTER"
								isMasterRouter=0																																				# Set flag if router IS NOT MR
							else
								echo -e "#"
								isMasterRouter=1	
							fi																																											# Set flag if router IS MR					
							echo -e "#"
							echo -e "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ [Rack: $a] Primary Router Failure\n"
							echo -e "------------ Sending \"$resetMethod\" command to router"
							routerFailure $a 5 $resetMethod $isMasterRouter
							echo -e "------------ Waiting for router to fail..."
							sleep 5
							echo -e "------------ Primary router has failed...\n------------ Waiting 5 minutes for take over"	
							sleep 300
							
							GigEcount=0
							echo -e "\nRe-creating [$a] PRIMARY Simulated IO:\n"
							for HID in ${coreIoInfo[@]}
							do
								echo -e "--------- Processing HID: $HID on GigE Port: $GigEcount"
								editSimBoxes $a 5 add 0 $HID $GigEcount $isMasterRouter
								sleep 5
								((GigEcount++))
							done	
					
						echo -e "\nSecondary patchstore:"
						sleep 2 
						validateSPC 6
						if [ $? != 1 ]
						then
							echo -e "------------------------ Test has FAILED\n" 
							date=$(date)
							echo -e "$date \npatchCount error when failing primary router on rack $a\n" >> logs/FAIL:$a.log		
#							gatherLogs $isMasterRouter $a 6				
#							Gather local and MR log here
						else
							echo -e "------------------------ Test has PASSED\n"
						fi
						
						echo -e "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ [Rack: $a] Secondary Router Failure\n"
						echo -e "------------ Sending \"$resetMethod\" command to router"
						routerFailure $a 6 $resetMethod $isMasterRouter
						echo -e "------------ Waiting for router to fail..."
						sleep 5
						echo -e "------------ Secondary router has failed...\n------------ Waiting 5 minutes for take over"	
						sleep 300
						
						GigEcount=0
						echo -e "\nRe-creating [$a] SECONDARY Simulated IO\n"
						for HID in ${coreIoInfo[@]}
						do
							echo -e "--------- Processing HID: $HID on GigE Port: $GigEcount"
							editSimBoxes $a 6 add 0 $HID $GigEcount $isMasterRouter
							sleep 5
							((GigEcount++))
						done	
						
						echo -e "\nPrimary patchstore:"
						sleep 2 
						validateSPC 5
						if [ $? != 1 ]
						then
							echo -e "------------------------ Test has FAILED\n" 
							date=$(date)
							echo -e "$date \npatchCount error when failing secondary router on rack $a" >> logs/FAIL:$a.log
#							gatherLogs $isMasterRouter $a 5				
#							Gather local and MR log here
						else
							echo -e "------------------------ Test has PASSED\n"
						fi
					done
					break					
					;; 
					"AutoPromotion")
						echo -e "Insert <AutoPromotion> tests"
						break
					;;
				esac
			done
			;;
		"Configure test system")
			echo -e "\nCONFIGURING SYSTEM"

			configureMenu=("View system info table" "Configure" "back")
			select confOpt in "${configureMenu[@]}"
			do		
				case $confOpt in
					"View system info table")
						coreID=0
						echo -e "\n| --Rack Level--| --DeskID-- | --rackType-- |         --Last IO config--         |\n"
						for localIOfor in ${deskIDs[@]}
						do
							lastIOs=($(<./.sys/conf/coreHIDs/$localIOfor.IOsetup))
							echo "| - 	${rackLevels[$coreID]}	    ${deskIDs[$coreID]}   	    ${rackTypes[$coreID]}		${lastIOs[@]} "
							((coreID++))
						done
						echo -e "\nDo you want to load this configuration onto the network? <Yes>/<No>"
						read loadConfig
						
						if [ $loadConfig == "Yes" ] || [ $loadConfig == "yes" ]
						then
							echo -e "CONFIGURATION LOAD"
							echo -e "Load configuration at <single> or <double> sample rate?"
							read isSampleRate
							
							for configCore in ${deskIDs[@]}
							do
								echo -e "---------------------------- RACK: $configCore"
								if [ $configCore != ${deskIDs[0]} ]																														# If "$coreToPopulate != "0" (MR) then "editSimBoxes" will 
								then																																									# need to ssh into MR then into slave router to build IO
									echo -e "CORE IS NOT MASTER ROUTER\n"
									isMasterRouter=0																																			# Set flag if router IS NOT MR
								else
									isMasterRouter=1																																			# Set flag if router IS MR
								fi
								
								GigEcount=0
								lastIOs=($(<./.sys/conf/coreHIDs/$configCore.IOsetup))
								for HID in ${lastIOs[@]}
								do				
									editSimBoxes $configCore 5 add 0 $HID $GigEcount $isMasterRouter $isSampleRate
									editSimBoxes $configCore 6 add 0 $HID $GigEcount $isMasterRouter $isSampleRate
									echo -e "---------------------------- Processing HID:	$HID"
									echo -e "---------------------------- GigE Port:		$GigEcount \n"
									((GigEcount++))
								done 	
							done						
						elif [ $loadConfig == "No" ] || [ $loadConfig == "no" ]
						then
							echo -e "Will not load...\n"
						else
							echo -e "Not a valid entry"
						fi											
						break
						;;
					"Configure")
						echo -e "\n------------------------------------------------------------------------------------------------------------"
						echo -e "\nIf you proceed past this point the existing configuration files will be removed. You will be required to complete this "
						echo -e "configuration in full if you answer yes... Proceed?"						
						echo -e "<Yes> / <No>"
						echo -e "\n------------------------------------------------------------------------------------------------------------\n"
						read usrProceed
						
						if [ $usrProceed == "Yes" ] || [ $usrProceed == "yes" ]
						then
						echo -e "\n---It is advised that you enter the system master router fist---\n"					
							./.sys/conf/config.sh
						elif [ $usrProceed == "No" ] || [ $usrProceed == "no" ]
						then
							break
						else
							echo -e "\n---Please answer properly!---\n"
							break
						fi
												
						echo -e "\n----- Please exit the program and re-launch for changes to take effect -----"
						break	
						;;
					"back")
						break
						;;
				esac
			done
			;;
		"Populate Core IO")																																									# Populate all routers defined in "DeskIDs" with IO

###########################################################################################
#							 Ask user for information about the intended core to populate with	#
#							 simulated IO + which sample rate to load the boxes at					#
###########################################################################################

			GigEcount=0
			echo -e "\nWould you like to <add> or <remove> IO boxes?"
			read addRm

			echo -e "\nWhich core would you like to populate / de-populate?"
			echo -e "\n  | --Rack Level--| --DeskID-- | --rackType-- |\n"
			echo "0:| - 	${rackLevels[0]}	    ${deskIDs[0]}   	    ${rackTypes[0]}      "
			echo "1:| - 	${rackLevels[1]}	    ${deskIDs[1]}   	    ${rackTypes[1]}	    "
			echo "2:| - 	${rackLevels[2]} 	    ${deskIDs[2]}   	    ${rackTypes[2]}	    "
			echo "3:| - 	${rackLevels[3]}	    ${deskIDs[3]}   	    ${rackTypes[3]}	    "
			echo "4:| - 	${rackLevels[4]}	    ${deskIDs[4]}   	    ${rackTypes[4]}	    "
			echo "5:| - 	${rackLevels[5]}	    ${deskIDs[5]}   	    ${rackTypes[5]}	    "
			echo "6:| - 	${rackLevels[6]}	    ${deskIDs[6]}   	    ${rackTypes[6]}	    "
			echo "7:| - 	${rackLevels[7]}	    ${deskIDs[7]}   	    ${rackTypes[7]}      "
			echo -e "\nPlease enter <0-7>"
			read coreToPopulate
			
			echo -e "\n--------------------------------------\n"
			echo -e "Ensure all physical links are plugged into ports 16 downwards, Simboxes will be created from port 0 up\n"
			echo -e "--------------------------------------\n"
			
			echo "How many physical links are present in the router?"																										# Ask user how many physical links are plugged into selected router
			read physicalLinks																																									# Store value in $physicalLinks variable
			
			physicalLinks=$((rackTypes[$coreToPopulate] - $physicalLinks))																								# Subtract $physicalLinks variable from the total number of GigE ports
																																																		# defined in the config file for selected router (8u / 4u)
																																						
			echo -e "\nTotal number of free GigE slots in" ${deskIDs[$coreToPopulate]} "= "$physicalLinks													# Display value of remaining (FREE) GigE ports
			echo -e "\n--------------------------------------\n"
			
			echo -e "Enter starting HID for SimBoxes on this rack"																											# Ask user to enter starting HID to loop up FROM && store in $HIDcounter
			read HIDcounter
			
			echo -e "\nSet simulated I/O sample rate\n <single> = single rate\n <double> = double rate"
			read isSampleRate
			
			maxHID=$(($HIDcounter + $physicalLinks))																															# Calculate the maximum HID value by adding the total physical links in $physicalLinks
			maxHID=$((maxHID-1))																																							# to the starting HID stored in $HIDcounter
			
			echo -e "\nIO will be created from HID: "$HIDcounter "to HID: " $maxHID 																				# Display the range of SimBoxes to be created on selected router
			
			loopCounter=$(($maxHID - $physicalLinks))
			
###########################################################################################
#							 Begin SimBoxes creation based on router info from user					#
#							  	  																						#
###########################################################################################				
				
			echo -e "\n------------------Processing "${deskIDs[$coreToPopulate]}"--------------------\n"																	# Begin SimBoxes creation
			if [ $rackLevels[$coreToPopulate] != $rackLevels[0] ]																												# If "$coreToPopulate != "0" (MR) then "editSimBoxes" will 
			then																																														# need to ssh into MR then into slave router to build IO
				echo -e "CORE IS NOT MASTER ROUTER\n\n"
				isMasterRouter=0																																								# Set flag if router IS NOT MR
			else
				isMasterRouter=1																																								# Set flag if router IS MR
			fi
			rm .sys/conf/coreHIDs/${deskIDs[$coreToPopulate]}.IOsetup																									# Remove existing text file w/ HIDs	
			
			while [ $loopCounter -lt $maxHID ]																																			# Create a single box in each free GiGe port on the router								
			do
				echo -e "Processing HID" $HIDcounter "on GigE port: "$GigEcount "\n"	
			
				editSimBoxes ${deskIDs[$coreToPopulate]} 5 $addRm 0 $HIDcounter $GigEcount	$isMasterRouter $isSampleRate				# Call "editSimBox" function using appropriate variables
				editSimBoxes ${deskIDs[$coreToPopulate]} 6 $addRm 0 $HIDcounter $GigEcount $isMasterRouter $isSampleRate				# NIC to both .5 + .6 (routers) then uncomment this line
				
				echo -n $HIDcounter "" >> .sys/conf/coreHIDs/${deskIDs[$coreToPopulate]}.IOsetup															# Write HIDs to text file w/ deskID tag	
				
				((HIDcounter++))
				((GigEcount++))
				((loopCounter++))
			
			done
			;;
		"Display current patch count")
			echo -e "\nDisplaying PRIMARY and SECONDARY patch count"
			validateSPC 5
			echo -e "\n Ping from PRIMARY master router:\n"
			mrPing 5
			echo -e "\n Ping from SECONDARY master router:\n"
			mrPing 6
			;;
		"Quit")
			break
			;;
		*) echo "invalid Option"
	esac
done
