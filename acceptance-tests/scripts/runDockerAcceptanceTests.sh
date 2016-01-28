#!/bin/bash
set -o errexit

cat <<EOF

 _    _  ___  ______ _   _ _____ _   _ _____ _ _ _ _ _
| |  | |/ _ \ | ___ \ \ | |_   _| \ | |  __ \ | | | | |
| |  | / /_\ \| |_/ /  \| | | | |  \| | |  \/ | | | | |
| |/\| |  _  ||    /| . ` | | | | . ` | | __| | | | | |
\  /\  / | | || |\ \| |\  |_| |_| |\  | |_\ \_|_|_|_|_|
 \/  \/\_| |_/\_| \_\_| \_/\___/\_| \_/\____(_|_|_|_|_)


THIS SCRIPT IS DEPRECATED!! IT'S LEFT FOR BACKWARDS COMPATIBILITY ONLY

PLEASE USE THE runAcceptanceTests.sh in the root folder of this repository.

EOF

# Functions
# Tails the log
function tail_log() {
    echo -e "\n\nLogs of [$1] jar app"
    tail -n $NUMBER_OF_LINES_TO_LOG build/"$1".log || echo "Failed to open log"
}

# Iterates over active containers and prints their logs to stdout
function print_logs() {
    echo -e "\n\nSomething went wrong... Printing logs:\n"

    docker ps | sed -n '1!p' > /tmp/containers.txt
    while read field1 field2 field3; do
      echo -e "\n\nContainer name [$field2] with id [$field1] logs: \n\n"
      docker logs --tail=$NUMBER_OF_LINES_TO_LOG -t $field1
    done < /tmp/containers.txt
    tail_log "brewing"
    tail_log "zuul"
    tail_log "presenting"
    tail_log "config-server"
    tail_log "eureka"
    tail_log "zookeeper"
    tail_log "zipkin-server"
}

# ${RETRIES} number of times will try to netcat to passed port $1 and host $2
function netcat_port() {
    local PASSED_HOST="${2:-$HEALTH_HOST}"
    local READY_FOR_TESTS=1
    for i in $( seq 1 "${RETRIES}" ); do
        sleep "${WAIT_TIME}"
        nc -v -z -w 1 $PASSED_HOST $1 && READY_FOR_TESTS=0 && break
        echo "Fail #$i/${RETRIES}... will try again in [${WAIT_TIME}] seconds"
    done
    return $READY_FOR_TESTS
}

# ${RETRIES} number of times will try to netcat to passed port $1 and localhost
function netcat_local_port() {
    netcat_port $1 "127.0.0.1"
}

# ${RETRIES} number of times will try to curl to /health endpoint to passed port $1 and host $2
function curl_health_endpoint() {
    local PASSED_HOST="${2:-$HEALTH_HOST}"
    local READY_FOR_TESTS=1
    for i in $( seq 1 "${RETRIES}" ); do
        sleep "${WAIT_TIME}"
        curl -m 5 "${PASSED_HOST}:$1/health" && READY_FOR_TESTS=0 && break
        echo "Fail #$i/${RETRIES}... will try again in [${WAIT_TIME}] seconds"
    done
    return $READY_FOR_TESTS
}

# ${RETRIES} number of times will try to curl to /health endpoint to passed port $1 and localhost
function curl_local_health_endpoint() {
    curl_health_endpoint $1 "127.0.0.1"
}

# Runs the `java -jar` for given application $1 and system properties $2
function java_jar() {
    local APP_JAVA_PATH=$1/build/libs
    local EXPRESSION="nohup $JAVA_HOME/bin/java $2 $MEM_ARGS -jar $APP_JAVA_PATH/*.jar >$APP_JAVA_PATH/nohup.log &"
    eval $EXPRESSION
    pid=$!
    echo $pid > $APP_JAVA_PATH/app.pid
    echo -e "\nJust started [$EXPRESSION]"
    echo -e "[$1] process pid is [$pid]"
    echo -e "System props are [$2]"
    echo -e "Logs are under [build/$1.log] or from nohup $APP_JAVA_PATH/nohup.log\n"
    return 0
}

# Starts the main brewery apps with given system props $1
function start_brewery_apps() {
    local REMOTE_DEBUG="-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address"
    java_jar "presenting" "$1 $REMOTE_DEBUG=8991"
    java_jar "brewing" "$1 $REMOTE_DEBUG=8992"
    java_jar "zuul" "$1 $REMOTE_DEBUG=8993"
    return 0
}

function kill_and_log() {
    kill -9 $(cat "$1"/build/libs/app.pid) && echo "Killed $1" || echo "Can't find $1 in running processes"
}
# Kills all started aps
function kill_all_apps() {
    echo `PWD`
    kill_and_log "brewing"
    kill_and_log "zuul"
    kill_and_log "presenting"
    kill_and_log "config-server"
    kill_and_log "eureka"
    kill_and_log "zookeeper"
    kill_and_log "zipkin-server"
    docker kill $(docker ps -q) || echo "No running docker containers are left"
    return 0
}

# Kills all started aps if the switch is on
function kill_all_apps_if_switch_on() {
    if [[ $KILL_AT_THE_END ]]; then
        echo -e "\n\nKilling all the apps"
        kill_all_apps
    else
        echo -e "\n\nNo switch to kill the apps turned on"
        return 0
    fi
    return 0
}

# Variables
CURRENT_DIR=`pwd`
REPO_URL="${REPO_URL:-https://github.com/spring-cloud-samples/brewery.git}"
REPO_BRANCH="${REPO_BRANCH:-master}"
if [[ -d acceptance-tests ]]; then
  REPO_LOCAL="${REPO_LOCAL:-.}"
else
  REPO_LOCAL="${REPO_LOCAL:-brewery}"
fi
WAIT_TIME="${WAIT_TIME:-5}"
RETRIES="${RETRIES:-70}"
DEFAULT_VERSION="${DEFAULT_VERSION:-Brixton.BUILD-SNAPSHOT}"
DEFAULT_HEALTH_HOST="${DEFAULT_HEALTH_HOST:-127.0.0.1}"
DEFAULT_NUMBER_OF_LINES_TO_LOG="${DEFAULT_NUMBER_OF_LINES_TO_LOG:-1000}"
SHOULD_START_RABBIT="${SHOULD_START_RABBIT:-yes}"
LOCALHOST="127.0.0.1"
MEM_ARGS="-Xmx64m -Xss1024k"

BOM_VERSION_PROP_NAME="BOM_VERSION"

# Parse the script arguments
while getopts ":t:v:h:n:r:k:n:x:s" opt; do
    case $opt in
        t)
            WHAT_TO_TEST="${OPTARG}"
            ;;
        v)
            VERSION="${OPTARG}"
            ;;
        h)
            HEALTH_HOST="${OPTARG}"
            ;;
        l)
            NUMBER_OF_LINES_TO_LOG="${OPTARG}"
            ;;
        r)
            RESET=1
            ;;
        k)
            KILL_AT_THE_END=1
            ;;
        n)
            KILL_NOW=1
            ;;
        x)
            NO_TESTS=1
            ;;
        s)
            SKIP_BUILDING=1
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            exit 1
            ;;
    esac
done

[[ -z "${WHAT_TO_TEST}" ]] && WHAT_TO_TEST=ZOOKEEPER
[[ -z "${VERSION}" ]] && VERSION="${DEFAULT_VERSION}"
[[ -z "${HEALTH_HOST}" ]] && HEALTH_HOST="${DEFAULT_HEALTH_HOST}"
[[ -z "${NUMBER_OF_LINES_TO_LOG}" ]] && NUMBER_OF_LINES_TO_LOG="${DEFAULT_NUMBER_OF_LINES_TO_LOG}"

HEALTH_PORTS=('9991' '9992' '9993')
HEALTH_ENDPOINTS="$( printf "http://${LOCALHOST}:%s/health " "${HEALTH_PORTS[@]}" )"

cat <<EOF

Running tests with the following parameters

HEALTH_HOST=${HEALTH_HOST}
WHAT_TO_TEST=${WHAT_TO_TEST}
VERSION=${VERSION}
NUMBER_OF_LINES_TO_LOG=${NUMBER_OF_LINES_TO_LOG}
KILL_AT_THE_END=${KILL_AT_THE_END}
KILL_NOW=${KILL_NOW}
NO_TESTS=${NO_TESTS}
NO_BUILD=${NO_BUILD}
SHOULD_START_RABBIT=${SHOULD_START_RABBIT}

EOF

export WHAT_TO_TEST=$WHAT_TO_TEST
export VERSION=$VERSION
export HEALTH_HOST=$HEALTH_HOST
export WAIT_TIME=$WAIT_TIME
export RETRIES=$RETRIES
export BOM_VERSION_PROP_NAME=$BOM_VERSION_PROP_NAME
export NUMBER_OF_LINES_TO_LOG=$NUMBER_OF_LINES_TO_LOG
export KILL_AT_THE_END=$KILL_AT_THE_END
export LOCALHOST=$LOCALHOST
export MEM_ARGS=$MEM_ARGS
export SHOULD_START_RABBIT=$SHOULD_START_RABBIT

export -f tail_log
export -f print_logs
export -f netcat_port
export -f netcat_local_port
export -f curl_health_endpoint
export -f curl_local_health_endpoint
export -f java_jar
export -f start_brewery_apps
export -f kill_all_apps
export -f kill_and_log

# Kill all apps and exit if switch set
if [[ $KILL_NOW ]] ; then
    echo -e "\nKilling all apps"
    kill_all_apps
    exit 0
fi

# Clone or update the brewery repository
if [[ ! -e "${REPO_LOCAL}/.git" ]]; then
    git clone "${REPO_URL}" "${REPO_LOCAL}"
    cd "${REPO_LOCAL}"
else
    cd "${REPO_LOCAL}"
    if [[ $RESET ]]; then
        git reset --hard
        git pull "${REPO_URL}" "${REPO_BRANCH}"
    fi
fi

echo -e "\nAppending if not present the following entry to gradle.properties\n"

# Update the desired BOM version
grep "${BOM_VERSION_PROP_NAME}=${VERSION}" gradle.properties || echo -e "\n${BOM_VERSION_PROP_NAME}=${VERSION}" >> gradle.properties

echo -e "\n\nUsing the following gradle.properties"
cat gradle.properties

echo -e "\n\n"

# Build the apps
if [[ -z "${SKIP_BUILDING}" ]] ; then
    ./gradlew clean build --parallel --no-daemon
fi

# Run the initialization script
INITIALIZATION_FAILED="yes"
./docker-compose-$WHAT_TO_TEST.sh && INITIALIZATION_FAILED="no"

if [[ "${INITIALIZATION_FAILED}" == "yes" ]] ; then
    echo "\n\nFailed to initialize the apps!"
    print_logs
    kill_all_apps_if_switch_on
    exit 1
fi

# Wait for the apps to boot up
APPS_ARE_RUNNING="no"

echo -e "\n\nWaiting for the apps to boot for [$(( WAIT_TIME * RETRIES ))] seconds"
for i in $( seq 1 "${RETRIES}" ); do
    sleep "${WAIT_TIME}"
    curl -m 5 ${HEALTH_ENDPOINTS} && APPS_ARE_RUNNING="yes" && break
    echo "Fail #$i/${RETRIES}... will try again in [${WAIT_TIME}] seconds"
done

if [[ "${APPS_ARE_RUNNING}" == "no" ]] ; then
    echo "\n\nFailed to boot the apps!"
    print_logs
    kill_all_apps_if_switch_on
    exit 1
fi

# Wait for the apps to register in Service Discovery
READY_FOR_TESTS="no"

echo -e "\n\nChecking for the presence of all services in Service Discovery for [$(( WAIT_TIME * RETRIES ))] seconds"
for i in $( seq 1 "${RETRIES}" ); do
    sleep "${WAIT_TIME}"
    curl -m 5 http://${LOCALHOST}:9991/health | grep presenting |
        grep brewing && READY_FOR_TESTS="yes" && break
    echo "Fail #$i/${RETRIES}... will try again in [${WAIT_TIME}] seconds"
done

if [[ "${READY_FOR_TESTS}" == "no" ]] ; then
    echo "\n\nThe apps failed to register in Service Discovery!"
    print_logs
    kill_all_apps_if_switch_on
    exit 1
fi

echo

# Run acceptance tests
TESTS_PASSED="no"

if [[ $NO_TESTS ]] ; then
    echo -e "\nSkipping end to end tests"
    kill_all_apps_if_switch_on
    exit 0
fi

if [[ "${READY_FOR_TESTS}" == "yes" ]] ; then
    echo -e "\n\nSuccessfully booted up all the apps. Proceeding with the acceptance tests"
    echo -e "\n\nRunning acceptance tests with the following parameters [-DWHAT_TO_TEST=${WHAT_TO_TEST} -DLOCAL_URL=http://${HEALTH_HOST}]"
    ./gradlew :acceptance-tests:acceptanceTests "-DWHAT_TO_TEST=${WHAT_TO_TEST}" "-DLOCAL_URL=http://${HEALTH_HOST}" --stacktrace --no-daemon --configure-on-demand && TESTS_PASSED="yes"
fi

# Check the result of tests execution
if [[ "${TESTS_PASSED}" == "yes" ]] ; then
    echo -e "\n\nTests passed successfully."
    kill_all_apps_if_switch_on
    exit 0
else
    echo -e "\n\nTests failed..."
    print_logs
    kill_all_apps_if_switch_on
    exit 1
fi