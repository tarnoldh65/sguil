# $Id: SguildTranscript.tcl,v 1.1 2004/10/05 15:23:20 bamm Exp $ #

proc InitRawFileArchive { date sensor srcIP dstIP srcPort dstPort ipProto } {
  global LOCAL_LOG_DIR DEBUG
  # Check to make sure our dirs exists. We use <rootdir>/date/sensorName/*.raw
  if { ! [file exists $LOCAL_LOG_DIR] } {
    if { [catch { file mkdir $LOCAL_LOG_DIR } mkdirError] } {
      # Problem creating LOCAL_LOG_DIR
      if { $DEBUG } {
        puts "Error: Unable to create $LOCAL_LOG_DIR for storing pcap data."
        puts " $mkdirError"
      }
      return -code error $mkdirError
    }
  }
  set dateDir "$LOCAL_LOG_DIR/$date"
  if { ! [file exists $dateDir] } {
    if { [catch { file mkdir $dateDir } mkdirError] } {
      # Problem creating dateDir
      if { $DEBUG } {
        puts "Error: Unable to create $dateDir for storing pcap data."
        puts " $mkdirError"
      }
      return -code error $mkdirError
    }
  }
  set sensorDir "$dateDir/$sensor"
  if { ![file exists $sensorDir] } {
    if { [catch { file mkdir $sensorDir }  mkdirError] } {
      # Problem creating sensorDir
      if { $DEBUG } {
        puts "Error: Unable to create $sensorDir for storing pcap data."
        puts " $mkdirError"
      }
      return -code error $mkdirError
    }
  }
  # We always make the highest port the apparent source. This way we don't store
  # two copies of the same raw data.
  if { $srcPort > $dstPort } {
    set rawDataFileName "${srcIP}:${srcPort}_${dstIP}:${dstPort}-${ipProto}.raw"
  } else {
    set rawDataFileName "${dstIP}:${dstPort}_${srcIP}:${srcPort}-${ipProto}.raw"
  }
  return [list $sensorDir $rawDataFileName]
}

proc EtherealRequest { socketID sensor timestamp srcIP srcPort dstIP dstPort ipProto force } {
  global TRANS_ID transInfoArray DEBUG LOCAL_LOG_DIR
    # Increment the xscript counter. Gives us a unique way to track the xscript
  incr TRANS_ID
  set date [lindex $timestamp 0]
  if [catch { InitRawFileArchive $date $sensor $srcIP $dstIP $srcPort $dstPort $ipProto }\
      rawDataFileNameInfo] {
    SendSocket $socketID "ErrorMessage Error getting pcap: $rawDataFileNameInfo"
    return
  }
  set sensorDir [lindex $rawDataFileNameInfo 0]
  set rawDataFileName [lindex $rawDataFileNameInfo 1]
  # A list of info we'll need when we generate the actual xscript after the rawdata is returned.
  set transInfoArray($TRANS_ID) [list $socketID null $sensorDir ethereal $sensor $timestamp ]
  if { ! [file exists $sensorDir/$rawDataFileName] || $force } {
    # No local archive (first request) or the user has requested we force a check for new data.
    if { ![GetRawDataFromSensor $TRANS_ID $sensor $timestamp $srcIP $srcPort $dstIP $dstPort $ipProto $rawDataFileName ethereal] } {
      # This means the sensor_agent for this sensor isn't connected.
      SendSocket $socketID "ErrorMessage ERROR: Unable to request rawdata at this time.\
       The sensor $sensor is NOT connected."
    }
  } else {
    # The data is archived locally.
    SendEtherealData $sensorDir/$rawDataFileName $TRANS_ID
  }
                                                                                                            
}

proc SendEtherealData { fileName TRANS_ID } {
  global DEBUG transInfoArray
                                                                                                            
  set clientSocketID [lindex $transInfoArray($TRANS_ID) 0]
  #puts $clientSocketID "EtherealDataBase64 [file tail $fileName] [file size $fileName]"
  # Clean up the filename for win32 systems
  regsub -all {:} [file tail $fileName] {_} cleanFileName
  puts $clientSocketID "EtherealDataPcap $cleanFileName [file size $fileName]"
  set rFileID [open $fileName r]
  fconfigure $rFileID -translation binary
  fconfigure $clientSocketID -translation binary
  fcopy $rFileID $clientSocketID
  fconfigure $clientSocketID -encoding utf-8 -translation {auto crlf}
  # Old stuff if we need to revert back to Base64 file xfers (yuck)
  #sock12 null /snort_data/archive/2004-06-10/gateway ethereal gateway {2004-06-10 17:21:56}
  #SendSocket $clientSocketID "EtherealDataBase64 [file tail $fileName] BEGIN"
  #set inFileID [open $fileName r]
  #fconfigure $inFileID -translation binary
  #foreach line [::base64::encode [read -nonewline $inFileID]] {
  #  SendSocket $clientSocketID "EtherealDataBase64 [file tail $fileName] $line"
  #}
  #SendSocket $clientSocketID "EtherealDataBase64 [file tail $fileName] END"
  #close $inFileID
}

proc XscriptRequest { socketID sensor winID timestamp srcIP srcPort dstIP dstPort force } {
  global TRANS_ID transInfoArray DEBUG LOCAL_LOG_DIR TCPFLOW
  # If we don't have TCPFLOW then error to the user and return
  if { ![info exists TCPFLOW] || ![file exists $TCPFLOW] || ![file executable $TCPFLOW] } {
      SendSocket $socketID "ErrorMessage ERROR: tcpflow is not installed on the server."
      SendSocket $socketID "XscriptDebugMsg $winID ERROR: tcpflow is not installed on the server."
    return
  }
  # Increment the xscript counter. Gives us a unique way to track the xscript
  incr TRANS_ID
  set date [lindex $timestamp 0]
  if [catch { InitRawFileArchive $date $sensor $srcIP $dstIP $srcPort $dstPort 6 }\
      rawDataFileNameInfo] {
    SendSocket $socketID\
     "ErrorMessage Please pass the following to your sguild administrator:\
      Error from sguild while getting pcap: $rawDataFileNameInfo"
    SendSocket $socketID "XscriptDebugMsg $winID\
     ErrorMessage Please pass the following to your sguild administrator:\
     Error from sguild while getting pcap: $rawDataFileNameInfo"
    SendSocket $socketID "XscriptMainMsg $winID DONE"
    return
  }
  set sensorDir [lindex $rawDataFileNameInfo 0]
  set rawDataFileName [lindex $rawDataFileNameInfo 1]
  # A list of info we'll need when we generate the actual xscript after the rawdata is returned.
  set transInfoArray($TRANS_ID) [list $socketID $winID $sensorDir xscript $sensor $timestamp ]
  if { ! [file exists $sensorDir/$rawDataFileName] || $force } {
    # No local archive (first request) or the user has requested we force a check for new data.
    if { ![GetRawDataFromSensor $TRANS_ID $sensor $timestamp $srcIP $srcPort $dstIP $dstPort 6 $rawDataFileName xscript] } {
      # This means the sensor_agent for this sensor isn't connected.
      SendSocket $socketID "ErrorMessage ERROR: Unable to request xscript at this time.\
       The sensor $sensor is NOT connected."
      SendSocket $socketID "XscriptDebugMsg $winID ERROR: Unable to request xscript at this time.\
       The sensor $sensor is NOT connected."
      SendSocket $socketID "XscriptMainMsg $winID DONE"
    }
  } else {
    # The data is archive locally.
    SendSocket $socketID "XscriptDebugMsg $winID Using archived data: $sensorDir/$rawDataFileName"
    GenerateXscript $sensorDir/$rawDataFileName $socketID $winID
  }
}

proc GetRawDataFromSensor { TRANS_ID sensor timestamp srcIP srcPort dstIP dstPort proto filename type } {
  global agentSocket connectedAgents DEBUG transInfoArray
  set RFLAG 1
  if { [array exists agentSocket] && [info exists agentSocket($sensor)]} {
    set sensorSocketID $agentSocket($sensor)
    if {$DEBUG} {
      puts "Sending $sensor: RawDataRequest $TRANS_ID $sensor $timestamp $srcIP $dstIP $dstPort $proto $filename $type"
    }
    if { [catch { puts $sensorSocketID\
         "[list RawDataRequest $TRANS_ID $sensor $timestamp $srcIP $dstIP $srcPort $dstPort $proto $filename $type]" }\
          sendError] } {
      catch { close $sensorSocketID } tmpError
      CleanUpDisconnectedAgent $sensorSocketID
      set RFLAG 0
    }
    flush $sensorSocketID
    if { $type == "xscript" } {
      SendSocket [lindex $transInfoArray($TRANS_ID) 0]\
       "XscriptDebugMsg [lindex $transInfoArray($TRANS_ID) 1] Raw data request sent to $sensor."
    }
  } else {
    set RFLAG 0
  }
  return $RFLAG
}

proc RawDataFile { socketID fileName TRANS_ID } {
  global DEBUG agentSensorName transInfoArray
  set type [lindex $transInfoArray($TRANS_ID) 3]
  if {$DEBUG} {puts "Recieving rawdata file $fileName."}
  if { $type == "xscript" } {
    SendSocket [lindex $transInfoArray($TRANS_ID) 0]\
     "XscriptDebugMsg [lindex $transInfoArray($TRANS_ID) 1] Recieving raw file from sensor."
  }
  fconfigure $socketID -translation binary
  set outfile [lindex $transInfoArray($TRANS_ID) 2]/$fileName
  set fileID [open $outfile w]
  fconfigure $fileID -translation binary
  # Copy the file from the binary socket
  fcopy $socketID $fileID
  catch {close $fileID}
  catch {close $socketID}
  if { $type == "xscript" } {
    GenerateXscript $outfile [lindex $transInfoArray($TRANS_ID) 0] [lindex $transInfoArray($TRANS_ID) 1]
  } elseif { $type == "ethereal" } {
    SendEtherealData $outfile $TRANS_ID
  }
}

proc XscriptDebugMsg { TRANS_ID msg } {
  global DEBUG transInfoArray
  SendSocket [lindex $transInfoArray($TRANS_ID) 0]\
     "XscriptDebugMsg [lindex $transInfoArray($TRANS_ID) 1] $msg"
}

proc GenerateXscript { fileName clientSocketID winName } {
  global TRANS_ID transInfoArray TCPFLOW DEBUG LOCAL_LOG_DIR P0F P0F_PATH
  set NODATAFLAG 1
  # We don't have a really good way for make xscripts yet and are unable
  # to figure out the true src. So we assume the low port was the server
  # port. We can get that info from the file name.
  # Filename example: 208.185.243.68:6667_67.11.255.148:3470-6.raw
  regexp {^(.*):(.*)_(.*):(.*)-([0-9]+)\.raw$} [file tail $fileName] allMatch srcIP srcPort dstIP dstPort ipProto
                                                                                                            
  set srcMask [TcpFlowFormat $srcIP $srcPort $dstIP $dstPort]
  set dstMask [TcpFlowFormat $dstIP $dstPort $srcIP $srcPort]
  SendSocket $clientSocketID "XscriptMainMsg $winName HDR"
  SendSocket $clientSocketID "XscriptMainMsg $winName Sensor Name:\t[lindex $transInfoArray($TRANS_ID) 4]"
  SendSocket $clientSocketID "XscriptMainMsg $winName Timestamp:\t[lindex $transInfoArray($TRANS_ID) 5]"
  SendSocket $clientSocketID "XscriptMainMsg $winName Connection ID:\t$winName"
  SendSocket $clientSocketID "XscriptMainMsg $winName Src IP:\t\t$srcIP\t([GetHostbyAddr $srcIP])"
  SendSocket $clientSocketID "XscriptMainMsg $winName Dst IP:\t\t$dstIP\t([GetHostbyAddr $dstIP])"
  SendSocket $clientSocketID "XscriptMainMsg $winName Src Port:\t\t$srcPort"
  SendSocket $clientSocketID "XscriptMainMsg $winName Dst Port:\t\t$dstPort"
  if {$P0F} {
    if { ![file exists $P0F_PATH] || ![file executable $P0F_PATH] } {
      SendSocket $clientSocketID "XscriptDebugMsg $winName Cannot find p0f in: $P0F_PATH"
      SendSocket $clientSocketID "XscriptDebugMsg $winName OS fingerprint has been disabled"
    } else {
      set p0fID [open "| $P0F_PATH -q -s $fileName"]
      while { [gets $p0fID data] >= 0 } {
        SendSocket $clientSocketID "XscriptMainMsg $winName OS Fingerprint:\t$data"
      }
      catch {close $p0fID} closeError
    }
  }
  # Depreciated with hdrTag in sguil.tk
  #SendSocket $clientSocketID "XscriptMainMsg $winName ================================================================================="
  SendSocket $clientSocketID "XscriptMainMsg $winName \n"
  if  [catch {open "| $TCPFLOW -c -r $fileName"} tcpflowID] {
    if {$DEBUG} {puts "ERROR: tcpflow: $tcpflowID"}
    SendSocket $clientSocketID "XscriptDebugMsg $winName ERROR: tcpflow: $tcpflowID"
    catch {close $tcpflowID}
    return
  }
  set state SRC
  while { [gets $tcpflowID data] >= 0 } {
    set NODATAFLAG 0
    if { [regsub ^$srcMask:\  $data {} data] > 0 } {
      set state SRC
    } elseif { [regsub ^$dstMask:\  $data {} data] > 0 } {
      set state DST
    }
    SendSocket $clientSocketID "XscriptMainMsg $winName $state"
    SendSocket $clientSocketID "XscriptMainMsg $winName $data"
  }
  if [catch {close $tcpflowID} closeError] {
    SendSocket $clientSocketID "XscriptDebugMsg $winName ERROR: tcpflow: $closeError"
  }
  if {$NODATAFLAG} {
    SendSocket $clientSocketID "XscriptMainMsg $winName No Data Sent."
  }
  SendSocket $clientSocketID "XscriptMainMsg $winName DONE"
  unset transInfoArray($TRANS_ID)
}
