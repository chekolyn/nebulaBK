#!/bin/bash

### Global variables script for parallel backup ###

# Uncomment or write a nebulabk-local-config.sh file to source from
# with the variables bellow:

# Credentials
#CREDENTIALS_DIR=$HOME/Nebula_Credentials
#ADMIN_CRED=$HOME/Nebula_Credentials/parc-xcloud-admin
#ADMIN_CRED=$HOME/Nebula_Credentials/parc-scloud-admin
#SCRIPT=openrc.sh
#NEW_BU_USER_CRED_FILE=$CREDENTIALS_DIR/tmp_new_bu_user_cred.sh

### TEST VARS ###
#TEST="N"
#TEST="Y"
#TEST_LIST="41e6d28a3ece4fcd82ded50017a5664e 663618ccba364ff1baea2c454ce68ea6"

# Parallel Jobs:
#TENANT_JOBS=4
#ACTION_JOBS=1

# Credentials and TEST Vars moved to local config file
# to eased production and dev enviroments.

# COLORS:
# Linux Colors
red='\e[0;31m'
yellow='\e[1;33m'
lt_red='\e[1;31m'
lt_brn='\e[0;33m'
lt_blue='\e[1;34m'
lt_grn='\e[1;32m'
NC='\e[0m' # No Color

## Dynamic Credentials and Test vars:
if [[ -f nebulabk-local-config.sh ]] ; then
	source  nebulabk-local-config.sh
fi

## Vars sanity check:
## Check for ADMIN Credentials vars:
if [[ -z "$ADMIN_CRED" ]] ; then
	echo -e "${red} --- No Admin credentials found. Exiting ... ${NC}"
	exit
fi

# Get Dynamic DIR based on the credentials:
OS_AUTH_URL_HOSTNAME=$(cat ${ADMIN_CRED}/${SCRIPT} | grep AUTH | awk -F'[//]' '{print $3}' | awk -F\: '{print $1}')


# Backup paths:
BK_DIR="/backups/$OS_AUTH_URL_HOSTNAME"
IMAGE_DIR="$BK_DIR/image-backup"
INSTANCE_DIR="$BK_DIR/instance-backup"
LOGDIR="$BK_DIR/logs"
LOGFILE="$BK_DIR/bu.log"

# Openstack commands:
NOVA_CMD="nova --insecure"
GLANCE_CMD="glance --insecure"
KEYSTONE_CMD="keystone --insecure"
SWIFT_CMD="swift --insecure"


### GLOBAL Functions ####

###############################################################################
###   -------------------------------------------------------------------   ###
###############################################################################

set_user()
{
	source ${ADMIN_CRED}/${SCRIPT}
}



###############################################################################
###   -------------------------------------------------------------------   ###
###############################################################################

show_credentials()
{
	echo "+-----------------------------------------------------------+"
	echo "| User Credentials"
	echo "+-----------------------------------------------------------+"
	echo "| `env | grep  OS_AUTH_URL`"
	echo "| `env | grep  OS_TENANT_ID`"
	echo "| `env | grep  OS_TENANT_NAME`"
	echo "| `env | grep  OS_USERNAME`"
	echo "| OS_PASSWORD=******"
	echo "+-----------------------------------------------------------+"
}

###############################################################################
###   -------------------------------------------------------------------   ###
###############################################################################

create_bu_user()
{
	# If BK user credential files exist don't add it again:
	if [[ -f $NEW_BU_USER_CRED_FILE ]] ; then
		echo "BU User file seems to be present ... not creating!"

	else

		# This is the name, etc. of a temporary, new user that will be used to d/l the images
		export NEW_BU_USER_NAME="IMAGE_BU_user"
		export NEW_BU_USER_PASS="secrete"
		export NEW_BU_TENANT_NAME="IMAGE_BU-Home"

		# Create New Backup User

		echo "| - Creating new backup user tenant (project) : $NEW_BU_TENANT_NAME"

		${KEYSTONE_CMD} tenant-create --name ${NEW_BU_TENANT_NAME} --description "Image backup project" --enabled true
		NEW_BU_OS_TENANT_ID=`${KEYSTONE_CMD} tenant-get ${NEW_BU_TENANT_NAME} | grep -w "id" | sed "s/ //g" | awk -F\| '{ print $3 }'`

		echo "| - Creating new backup user name - ${NEW_BU_USER_NAME}"

		${KEYSTONE_CMD}  user-create --name ${NEW_BU_USER_NAME} --tenant ${NEW_BU_OS_TENANT_ID}  --pass ${NEW_BU_USER_PASS}  --email "image-backup@nebula.com" --enabled true
		NEW_BU_USER_ID=`${KEYSTONE_CMD}  user-list | grep -w "${NEW_BU_USER_NAME}" | sed "s/ //g" | awk -F\| '{ print $2 }'`

		# Sanity check, delete file if exists:
		if [[ -f $NEW_BU_USER_CRED_FILE ]] ; then
			rm $NEW_BU_USER_CRED_FILE
		fi

		# Write new temp bu user to file #
		touch $NEW_BU_USER_CRED_FILE
		echo ""export NEW_BU_OS_TENANT_ID="${NEW_BU_OS_TENANT_ID}" "" >> $NEW_BU_USER_CRED_FILE
		echo ""export NEW_BU_USER_PASS="${NEW_BU_USER_PASS}" "" >> $NEW_BU_USER_CRED_FILE
		echo ""export NEW_BU_USER_ID="${NEW_BU_USER_ID}" "" >> $NEW_BU_USER_CRED_FILE
	fi
}

###############################################################################
###   -------------------------------------------------------------------   ###
###############################################################################

get_bu_user()
{
	# If new_bu file exist get it from the file:
	if [[ -f $NEW_BU_USER_CRED_FILE ]] ; then
		source $NEW_BU_USER_CRED_FILE
	else
		NEW_BU_TENANT_NAME="IMAGE_BU-Home"
		NEW_BU_USER_NAME="IMAGE_BU_user"

		NEW_BU_USER_ID=`${KEYSTONE_CMD}  user-list | grep -w "${NEW_BU_USER_NAME}" | sed "s/ //g" | awk -F\| '{ print $2 }'`
		NEW_BU_OS_TENANT_ID=`${KEYSTONE_CMD} tenant-get ${NEW_BU_TENANT_NAME} | grep -w "id" | sed "s/ //g" | awk -F\| '{ print $3 }'`

	fi

}

show_bu_user()
{
	get_bu_user

	echo "NEW_BU_USER_ID $NEW_BU_USER_ID"
	echo "NEW_BU_OS_TENANT_ID $NEW_BU_OS_TENANT_ID"

}

###############################################################################
###   -------------------------------------------------------------------   ###
###############################################################################

delete_bu_user()
{
	# Get the user from file:
	get_bu_user

	# Delete New Backup User
	echo "| GLOBAL - Deleting new backup user name - ${NEW_BU_USER_NAME}"
	${KEYSTONE_CMD} user-delete ${NEW_BU_USER_ID}
	echo "| GLOBAL - Deleting new backup user tenant (project) : $NEW_BU_TENANT_NAME"
	${KEYSTONE_CMD} tenant-delete ${NEW_BU_OS_TENANT_ID}

	# Remove Credentials file:
	rm $NEW_BU_USER_CRED_FILE

	export NEW_BU_USER_NAME=""
	export NEW_BU_USER_PASS=""
	export NEW_BU_TENANT_NAME=""
}

###############################################################################
###   -------------------------------------------------------------------   ###
###############################################################################

roles()
{
	# Get roles
	MEMBER_ROLE=`${KEYSTONE_CMD}  role-list | grep "Member" | sed "s/ //g" | awk -F\| '{ print $2 }'`
	ADMIN_ROLE=`${KEYSTONE_CMD}  role-list | grep "Admin" | sed "s/ //g" | awk -F\| '{ print $2 }'`

}


###############################################################################
###   -------------------------------------------------------------------   ###
###############################################################################

add_user_to_project()
{
	local PROJECT=$1

	if [ "$#" -ne 1 ] ; then
		echo "GLOBAL Function add_user_to_project: Not enoght arguments..."
		exit
	fi

	# Get the user from file:
	get_bu_user

	# Get roles:
	roles

	echo "| - Adding BU User To Project"

	${KEYSTONE_CMD} user-role-add --user ${NEW_BU_USER_ID} --role ${MEMBER_ROLE} --tenant $PROJECT
	PROJECT_NAME=`${KEYSTONE_CMD}  tenant-list | grep ${PROJECT} | sed "s/ //g" | awk -F\| '{ print $3 }'`
	export OS_TENANT_ID=${PROJECT}
	export OS_TENANT_NAME=${PROJECT_NAME}

	echo "| Adding New User NAME : ${NEW_BU_USER_NAME}"
	echo "| To Tenant (Project) : ${PROJECT}"
	echo "| To Tenant (Project) Name : ${PROJECT_NAME}"
}

###############################################################################
###   -------------------------------------------------------------------   ###
###############################################################################

set_bu_user()
{
	# Get the user from file:
	get_bu_user

	export OS_USERNAME=$NEW_BU_USER_NAME
	export OS_PASSWORD=$NEW_BU_USER_PASS

}

###############################################################################
###   -------------------------------------------------------------------   ###
###############################################################################

delete_user_from_project()
{
	if [ "$#" -ne 1 ] ; then
		echo "GLOBAL Function delete_user_from_project: Not enoght arguments..."
		exit
	fi
	local PROJECT=$1

	${KEYSTONE_CMD} user-role-remove --user ${NEW_BU_USER_ID} --role ${MEMBER_ROLE} --tenant $PROJECT
}

set_project_realm()
{
	if [ "$#" -ne 1 ] ; then
		echo "GLOBAL Function set_project_realm: Not enoght arguments..."
		exit
	fi

	local PROJECT=$1

	PROJECT_NAME=`${KEYSTONE_CMD}  tenant-list | grep ${PROJECT} | sed "s/ //g" | awk -F\| '{ print $3 }'`
	export OS_TENANT_ID=${PROJECT}
	export OS_TENANT_NAME=${PROJECT_NAME}

}

get_project_name()
{
	if [ "$#" -ne 1 ] ; then
		echo "GLOBAL Function get_project_name: Not enoght arguments..."
		exit
	fi

	local PROJECT=$1
	export PROJECT_ID=$OS_TENANT_ID
	export PROJECT_NAME=$OS_TENANT_NAME

}


###############################################################################
###   -------------------------------------------------------------------   ###
###############################################################################

show_vars()
{
	echo -e "${lt_brn}+---------------------------------------------------------------------------------------+"
	echo    "+--------------------------        PRINT VARIABLES        ------------------------------+"
	echo -e "+---------------------------------------------------------------------------------------+${NC}"

	show_credentials

	echo "ADMIN_CRED: ${ADMIN_CRED}"

	echo "+++ BU User +++"
	show_bu_user

	echo "+++ TEST VARS +++"
	echo "TEST= ${TEST}"
	echo "TEST_LIST:"
	echo $TEST_LIST

	echo "+++ PROJECT INFO +++"
	echo "PROJECT: ${PROJECT}"
	echo "PROJECT_NAME: ${PROJECT_NAME}"
	echo "DIR: ${DIR}"
	echo "INSTANCE_DIR: $INSTANCE_DIR"
	echo "IMAGE_DIR: $IMAGE_DIR"

	echo "+++ Nebula User +++"
	env | grep OS
}
