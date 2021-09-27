#!/bin/bash

DEBUG=1

CLUSTER_INSIDE=0
CLUSTER_OUTSIDE=1

TASKSET_PATH="/usr/bin/taskset"
TCPDUMP_PATH="/usr/local/src/deri/PF_RING/userland/tcpdump/tcpdump"
NGREP_PATH="/usr/local/src/ngrep/pf_ngrep/ngrep"
HTTPRY_PATH="/usr/local/src/httpry/pf_httpry/httpry"

CORES_NUMA_OUTSIDE="0-7,16-23"
CORES_NUMA_INSIDE="8-15,24-31"

if [[ $DEBUG == 1 ]] ; then
   echo "DEBUG: Script "$0" started!"
fi

# Controllo che i comandi implementati nello script siano presenti nelle path indicate
if [ ! -e $TASKSET_PATH ] || [ ! -x $TASKSET_PATH ] ; then
   echo "ERROR: taskset is not correctly installed in the specified path!"
   echo "       ("$TASKSET_PATH")" ; exit 1
fi
if [ ! -e $TCPDUMP_PATH ] || [ ! -x $TCPDUMP_PATH ] ; then
   echo "ERROR: tcpdump is not correctly installed in the specified path!"
   echo "       ("$TCPDUMP_PATH")" ; exit 1
fi
if [ ! -e $NGREP_PATH ] || [ ! -x $NGREP_PATH ] ; then
   echo "ERROR: ngrep is not correctly installed in the specified path!"
   echo "       ("$NGREP_PATH")" ; exit 1
fi
if [ ! -e $HTTPRY_PATH ] || [ ! -x $HTTPRY_PATH ] ; then
   echo "ERROR: httpry is not correctly installed in the specified path!"
   echo "       ("$HTTPRY_PATH")" ; exit 1
fi

# Controllo che ci siano almeno 2 parametri
if [ -z $1 ] || [ -z $2 ] ; then
   echo "ERROR: Usage: "$0" inside|outside tcpdump|ngrep|httpry [parameters] [external parameters]" ; exit 1
fi

# Controllo che il primo parametro (il punto dove effettuare l'acquisizione) sia corretto e che esista il rispettivo processo zbalance_ipc
if [[ $1 == "INSIDE" ]] || [[ $1 == "inside" ]] ; then
   PID_CLUSTER=`ps aux | grep zbalance_ipc | egrep '\-c'$CLUSTER_INSIDE' ' | tr -s " " | cut -d" " -f2`
   PROBE="inside"
elif [[ $1 == "OUTSIDE" ]] || [[ $1 == "outside" ]] ; then
   PID_CLUSTER=`ps aux | grep zbalance_ipc | egrep '\-c'$CLUSTER_OUTSIDE' ' | tr -s " " | cut -d" " -f2`
   PROBE="outside"
else
   echo "ERROR: Unknown \""$1"\" parameter. It should be \"inside\"/\"INSIDE\" or \"outside\"/\"OUTSIDE\"." ; exit 1
fi

if [ -z $PID_CLUSTER ] ; then
   echo "ERROR: The zbalance_ipc "$PROBE" process is not up and running!" ; exit 1
fi

if [[ $DEBUG == 1 ]] ; then
   echo "DEBUG: Probe position: "$PROBE", zbalance_ipc PID: "$PID_CLUSTER
fi

# Controllo che il secondo paramentro (il comando) sia fra quelli implementati
if [[ $2 != "tcpdump" ]] && [[ $2 != "ngrep" ]] && [[ $2 != "httpry" ]] ; then
   echo "ERROR: Unknown \""$2"\" command. It should be \"tcpdump\" or \"ngrep\" or \"httpry\"." ; exit 1
fi

if [[ $DEBUG == 1 ]] ; then
   echo "DEBUG: Command to launch: "$2
fi

# Debug: scrivere a video il contenuto dei parametri passati allo script
if [[ $DEBUG == 1 ]] && [ -n $1 ] ; then
   echo "DEBUG: Parameter #1 => "$1
fi
if [[ $DEBUG == 1 ]] && [ -n $2 ] ; then
   echo "DEBUG: Parameter #2 => "$2
fi
#if [[ $DEBUG == 1 ]] && [ -n "$3" ] ; then
#   echo "DEBUG: Parameter #3 => "$3
#fi
if [[ $DEBUG == 1 ]] && [[ $# == 2 ]] ; then
   echo "DEBUG: Parameter #3 not defined!"
   echo "DEBUG: Parameter #4 not defined!"
fi
if [[ $DEBUG == 1 ]] && [[ $# == 3 ]] ; then
   echo "DEBUG: Parameter #3 => "$3
   echo "DEBUG: Parameter #4 not defined!"
fi
if [[ $DEBUG == 1 ]] && [[ $# == 4 ]] ; then
   echo "DEBUG: Parameter #3 => "$3
   echo "DEBUG: Parameter #4 => "$4
fi
#if [[ $DEBUG == 1 ]] && [[ $# == 3 ]] ; then
#   echo "DEBUG: Parameter #4 not defined!"
#fi

# Estraggo il numero totale di code implementate dal processo zbalance_ipc
TOT_QUEUES=`cat /proc/net/pf_ring/stats/$PID_CLUSTER-none* | grep TotQueues | tr -s " " | cut -d" " -f2`

if [ -z $TOT_QUEUES ] ; then
   echo "CRITICAL ERROR: There is a problem into the "$0" script! [TOT_QUEUES]"
fi

if [[ $DEBUG == 1 ]] ; then
   echo "DEBUG: Queues theorically available for the \""$2"\" command: "$TOT_QUEUES
fi

# Lancio il comando richiesto con i parametri corretti cercando la prima interfaccia disponibile
if [[ $PROBE == "inside" ]] ; then
   FIRST_QUEUE=0
   CLUSTER=$CLUSTER_INSIDE
   CORES_NUMA=$CORES_NUMA_INSIDE
else
   FIRST_QUEUE=0
   CLUSTER=$CLUSTER_OUTSIDE
   CORES_NUMA=$CORES_NUMA_OUTSIDE
fi

for I in $(seq $FIRST_QUEUE $((TOT_QUEUES - 1))) ; do
   INTERFACE="zc:"$CLUSTER"@"$I
   if [[ $DEBUG == 1 ]] ; then
      echo "DEBUG: Trying to use the "$INTERFACE" interface."
   fi
   case $2 in
      tcpdump)
         if [[ $DEBUG == 1 ]] ; then
            echo "DEBUG: Used command: "$TASKSET_PATH" "-ac" "$CORES_NUMA" "$TCPDUMP_PATH" -i "$INTERFACE" -nK -s0 "$3" "$4
         fi
         COMMAND="$TASKSET_PATH -ac $CORES_NUMA $TCPDUMP_PATH -i $INTERFACE -nK -s0 $3 $4"
         eval $COMMAND
         EXIT_CODE=$?
         if [[ $DEBUG == 1 ]] ; then
            echo "DEBUG: Exit code ["$EXIT_CODE"]."
         fi
         case $EXIT_CODE in
            0) 
               if [[ $DEBUG == 1 ]] ; then
                  echo "DEBUG: The command "$2" seems ended successfully!"
               fi
               break
               ;;
            1)
               if [[ $DEBUG == 1 ]] ; then
                  echo "DEBUG: Interface "$INTERFACE" already used!"
               fi
               continue
               ;;
            *)
               echo "CRITICAL ERROR: There is a problem into the "$0" script! [TCPDUMP]"
               ;;
         esac
         ;;
      ngrep)
         if [[ $DEBUG == 1 ]] ; then
            echo "DEBUG: Used command: "$TASKSET_PATH" "-ac" "$CORES_NUMA" "$NGREP_PATH" -d "$INTERFACE" -q -c72 "$3" "$4
         fi
         COMMAND="$TASKSET_PATH -ac $CORES_NUMA $NGREP_PATH -d $INTERFACE -q -c72 $3 $4"
         eval $COMMAND
         EXIT_CODE=$?
         if [[ $DEBUG == 1 ]] ; then
            echo "DEBUG: Exit code ["$EXIT_CODE"]."
         fi
         case $EXIT_CODE in
            0|1|2)
               if [[ $DEBUG == 1 ]] ; then
                  echo "DEBUG: The command "$2" seems ended successfully!"
               fi
               break
               ;;
            255)
               if [[ $DEBUG == 1 ]] ; then
                  echo "DEBUG: Interface "$INTERFACE" already used!"
               fi
               continue
               ;;
            *)
               echo "CRITICAL ERROR: There is a problem into the "$0" script! [NGREP]"
               ;;
         esac
         ;;
      httpry)
         if [[ $DEBUG == 1 ]] ; then
            echo "DEBUG: Used command: "$TASKSET_PATH" "-ac" "$CORES_NUMA" "$HTTPRY_PATH" -i "$INTERFACE" "$3" "$4
         fi
         COMMAND="$TASKSET_PATH -ac $CORES_NUMA $HTTPRY_PATH -i $INTERFACE $3 $4"
         eval $COMMAND
         EXIT_CODE=$?
         if [[ $DEBUG == 1 ]] ; then
            echo "DEBUG: Exit code ["$EXIT_CODE"]."
         fi
         case $EXIT_CODE in
            0)
               if [[ $DEBUG == 1 ]] ; then
                  echo "DEBUG: The command "$2" seems ended successfully! [0]"
               fi
               break
               ;;
            2)
               if [[ $DEBUG == 1 ]] ; then
                  echo "DEBUG: The command "$2" seems ended successfully! [2]"
               fi
               break
               ;;
            201)
               if [[ $DEBUG == 1 ]] ; then
                  echo "DEBUG: Interface "$INTERFACE" already used!"
               fi
               continue
               ;;
            *)
               echo "CRITICAL ERROR: There is a problem into the "$0" script! [HTTPRY]"
               ;;
         esac
         ;;
      *)
         echo "CRITICAL ERROR: There is a problem into the "$0" script! [COMMAND]"
         ;;
   esac
done

if [[ $2 == "tcpdump" ]] && [[ $EXIT_CODE == 1 ]] || [[ $2 == "ngrep" ]] && [[ $EXIT_CODE == 255 ]] ; then
   echo "CRITICAL ERROR: No ZC interface available for the "$2" command."
   exit 1
fi

if [[ $DEBUG == 1 ]] ; then
   echo "DEBUG: Script "$0" seems ended successfully!"
fi

exit 0
