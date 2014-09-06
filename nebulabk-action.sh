#!/bin/bash

# This script is ment to be run in parallel
# part of the nebulabk

# Load Global vars and functions
source nebulabk-global.sh

###############################################################################
###                                 FUNCTIONS                               ###
###############################################################################

###############################################################################
###   -------------------------------------------------------------------   ###
###############################################################################

create_snapshots()
{
	local PROJ=$1

	echo -e "${lt_grn}+---------------------------------------------------------------------------------------+"
	echo "+---------------------------------- Create Snapshots -----------------------------------+"
	echo -e "+---------------------------------------------------------------------------------------+${NC}"

	if [ ! -d ${INSTANCE_DIR} ]
	then
		  mkdir -p ${INSTANCE_DIR}
	fi

	echo "| Instance Snapshots stored in : ${INSTANCE_DIR}"
	echo "+---------------------------------------------------------------------------------------+"
	echo "| - Become cloud admin"
	set_user admin
	echo "| - Add bu user to project: "
	add_user_to_project ${PROJ}

	echo "+----------------------- Snapshot and back up Project Instances ------------------------+"
	DIR="${INSTANCE_DIR}/${PROJECT}_${PROJECT_NAME}"
	snapshot ${PROJ} ${DIR}

	echo "| - delete temp backup user from project"
	set_user admin
	delete_user_from_project ${PROJ}
	echo "+---------------------------------------------------------------------------------------+"
}

###############################################################################
###   -------------------------------------------------------------------   ###
###############################################################################

snapshot()
{
	local PROJECT=$1
	local DIR=$2

	DIR="${INSTANCE_DIR}/${PROJECT}_${PROJECT_NAME}"

	mkdir -p ${DIR}

	echo "| "
	echo -e "| ${lt_brn} make dir ${DIR} ${NC}"
	echo "| "

	echo "+---------------------------- Snapshot and Backup Instances  ---------------------------+"
	snapshot_save_instances_parallel ${PROJECT} ${DIR}

}

###############################################################################
###   -------------------------------------------------------------------   ###
###############################################################################

snapshot_save_instances_parallel()
{
	local PROJECT=$1
	local DIR=$2
	local INSTANCE
	local INSTANCE_NAME
	local IMAGE
	local NEW_IMAGE_NAME
	local DISK_FORMAT

	if [ "$#" -ne 2 ] ; then
		echo "Function snapshot_save_instances_parallel: Not enoght arguments... terminating"
		exit
	fi

	# IMPORTANT:
	set_bu_user

	# Show list of instances:
	${NOVA_CMD} list --tenant

	#show_vars

	# EXPORT Function for Parallel:
	export -f snapshot_save_single_instance

	LIST=`${NOVA_CMD} list --tenant | grep -wi "active" | sed "s/ //g" | awk -F\| '{ print $2 }'`
	echo "| *** ACTION: snapshot_save_instances_parallel: LIST for parallel command ****"
	echo "| Instances ID :"
	echo ${LIST}
	echo "|"

	# Run snapshot in parallel:
	parallel -j $ACTION_JOBS snapshot_save_single_instance ::: $LIST ::: $PROJECT ::: $PROJECT_NAME ::: $DIR ::: $TEST

}

###############################################################################
###   -------------------------------------------------------------------   ###
###############################################################################

snapshot_save_single_instance()
{
	# Include Global variables:
	source nebulabk-global.sh

	local INSTANCE=$1
	local PROJECT=$2
	local PROJECT_NAME=$3
	local DIR=$4
	local TEST=$5
	local INSTANCE_NAME
	local IMAGE
	local NEW_IMAGE_NAME
	local DISK_FORMAT

	if [ "$#" -ne 5 ] ; then
		echo "Function snapshot_save_single_instance: Not enoght arguments... terminating"
		exit
	fi

	# Important:
	set_bu_user

	INSTANCE_NAME=`${NOVA_CMD} list | grep ${INSTANCE} | awk -F\| '{ print $3 }' | sed -e "s/^ //g" -e "s/[ ]*$//g"`
	INSTANCE_IMAGE_SOURCE_ID=`${NOVA_CMD} show ${INSTANCE} | grep image | sed "s/.*(\(.*\)).*/\1/"`
	IMAGE_SOURCE_DISK_FORMAT=`${GLANCE_CMD} image-show ${INSTANCE_IMAGE_SOURCE_ID} | grep disk_format |  sed "s/ //g"  |  awk -F\| '{ print $3 }'`

	if [[ ${IMAGE_SOURCE_DISK_FORMAT} != "qcow2" ]] ; then
		echo "Skiping ${INSTANCE_NAME}  image source file is not QCOW2"
		${NOVA_CMD} show ${INSTANCE}
		${GLANCE_CMD} image-show ${INSTANCE_IMAGE_SOURCE_ID}
		exit
	fi

	echo "| Instance ID : ${INSTANCE}"
	echo "| Instance Name : ${INSTANCE_NAME}"
	DATE=`date +%m%d%Y-%H:%M:%S`
	NEW_IMAGE_NAME=${INSTANCE_NAME}.bu_snap.${DATE}
	echo "| ${NOVA_CMD} image-create --show --poll ${INSTANCE}  ${NEW_IMAGE_NAME}"

	if [[ $TEST != "Y" ]] ; then
		echo "| Image create start: $(date)"
		${NOVA_CMD} image-create --show --poll ${INSTANCE}  "${NEW_IMAGE_NAME}"
		echo "| Image create end: $(date)"
	fi

	echo "|"

	DIR="${INSTANCE_DIR}/${PROJECT}_${PROJECT_NAME}"

	if [[ $TEST == "Y" ]] ; then
		# for now just echo the commands - to actually d/l the images comment out this and uncomment the following line
		echo '| Glance downlowding file: ${DIR}/${IMAGE_NAME}.${DISK_FORMAT}'
		echo "| Glance download start: $(date)"
		echo '${GLANCE_CMD} image-download --file "${DIR}/${IMAGE_NAME}.${DISK_FORMAT}" --progress ${IMAGE}'
		echo "| Glance download end: $(date)"
		echo '| File status: $(file ${DIR}/${IMAGE_NAME}.${DISK_FORMAT})'
		echo '| Glance deleting temp snapshot ${NEW_IMAGE_NAME}'
		echo '${NOVA_CMD} image-delete ${NEW_IMAGE_NAME}'
		echo "|"
	else
		echo "| Image info:"
		${GLANCE_CMD} image-list --owner ${PROJECT} | grep  "${NEW_IMAGE_NAME}"
		IMAGE=`${GLANCE_CMD} image-list --owner ${PROJECT} | grep "${NEW_IMAGE_NAME}" | grep -w "active" | sed "s/ //g" | awk -F\| '{ print $2 }'`
		IMAGE_NAME=`${GLANCE_CMD} image-list | grep ${IMAGE} | awk -F\| '{ print $3 }' | sed -e "s/^ //g" -e "s/[ ]*$//g"`
		DISK_FORMAT=`${GLANCE_CMD} image-list | grep ${IMAGE} | grep "${NEW_IMAGE_NAME}" | sed "s/ //g" | awk -F\| '{ print $4 }'`

		echo "| NEW Image ID : ${IMAGE}"
		echo "| NEW Image Name : ${IMAGE_NAME}"
		echo "| NEW Image Format : ${DISK_FORMAT}"

		# Check if directory exist
		if [[ -d ${DIR} ]] ; then
			mkdir -p $DIR
		fi

		echo "| Glance downlowding file: ${DIR}/${IMAGE_NAME}.${DISK_FORMAT}"
		echo "| Glance download start: $(date)"
		${GLANCE_CMD} image-download --file "${DIR}/${IMAGE_NAME}.${DISK_FORMAT}" --progress ${IMAGE}
		echo "| Glance download end: $(date)"
		#echo ""| File status: $(file "${DIR}/${IMAGE_NAME}.${DISK_FORMAT}")""
		echo "| Glance deleting temp snapshot ${NEW_IMAGE_NAME}"
		${NOVA_CMD} image-delete "${NEW_IMAGE_NAME}"
		echo "|"

	fi

}

###############################################################################
###   -------------------------------------------------------------------   ###
###############################################################################

download_images()
{
	local PROJECT=$1
	local DIR

	set_user admin

	add_user_to_project ${PROJECT}
	DIR="${IMAGE_DIR}/${PROJECT}_${PROJECT_NAME}"

	mkdir -p ${DIR}
	echo "| "
	echo -e "| ${lt_brn} make dir ${DIR} ${NC}"
	echo "|"

	set_bu_user

	echo "+------------------------------------- Save Images -------------------------------------+"
	save_bu_images_parallel ${PROJECT} ${DIR}

	set_user admin
	delete_user_from_project ${PROJECT}

}

###############################################################################
###   -------------------------------------------------------------------   ###
###############################################################################

save_bu_images_parallel()
{
	# Include Global variables:
	source nebulabk-global.sh

	local PROJECT=$1
	local DIR=$2

	set_bu_user

	echo "TEST ${TEST}"
	#show_vars

	echo "+---------------------------------------------------------------------------------------+"
	echo -e "| ${lt_grn} Tenant ID: $PROJECT Name: $PROJECT_NAME  ${NC}"
	echo "+---------------------------------------------------------------------------------------+"

	# List images:
	${GLANCE_CMD} image-list --owner $PROJECT
	LIST=`${GLANCE_CMD} image-list --owner $PROJECT | grep -wi "active" | sed "s/ //g" | awk -F\| '{ print $2 }'`

	# EXPORT Function for Parallel:
	export -f download_single_image

	# Execute if list has items:
	if [[ $LIST == "" ]] ; then
		echo "+---------------------------------------------------------------------------------------+"
		echo -e "| ${lt_brn} --- SKIPPING no images to download--- ${NC}"
		echo "+---------------------------------------------------------------------------------------+"

	else
		# Run downloads in parallel:
		parallel -j $ACTION_JOBS download_single_image ::: $LIST ::: $PROJECT ::: $PROJECT_NAME ::: $DIR ::: $TEST
	fi

}

download_single_image()
{
	# Include Global variables:
	source nebulabk-global.sh

	local IMAGE_ID=$1
	local PROJECT=$2
	local PROJECT_NAME=$3
	local DIR=$4
	local TEST=$5

	if [ "$#" -ne 5 ] ; then
		echo -e "${red} Function snapshot_save_single_instance: Not enoght arguments... terminating ${NC}"
		exit
	fi

	# Important:
	set_bu_user

	# Image vars:
	IMAGE_FULL_INFO=$(${GLANCE_CMD} image-show $IMAGE_ID)
	IMAGE_OWNER=$( echo "${IMAGE_FULL_INFO}" | grep " owner" | sed "s/ //g" | awk -F\| '{ print $3 }')
	IMAGE_SIZE=$( echo "${IMAGE_FULL_INFO}" | grep size | sed "s/ //g" | awk -F\| '{ print $3 }')
	IMAGE_NAME=$( echo "${IMAGE_FULL_INFO}" | grep name  | awk -F\| '{ print $3 }' | sed -e "s/^ //g" -e "s/[ ]*$//g")
	IMAGE_DISK_FORMAT=$( echo "${IMAGE_FULL_INFO}" | grep disk_format |  sed "s/ //g"  |  awk -F\| '{ print $3 }')

	DIR="${IMAGE_DIR}/${PROJECT}_${PROJECT_NAME}"
	FILE_NAME="${IMAGE_NAME}.${IMAGE_DISK_FORMAT}"

	DOWNLOAD=true

	echo "| +++ IMAGE INFO +++"
	echo "$IMAGE_FULL_INFO"
	echo "| +++ VARS INFO +++"
	echo "IMAGE NAME:$IMAGE_NAME"
	echo "IMAGE SIZE:$IMAGE_SIZE"
	echo "IMAGE OWNER:$IMAGE_OWNER"
	echo "DISK FORMAT:$IMAGE_DISK_FORMAT"

	# Validate image ownership:
	if [[ $PROJECT != $IMAGE_OWNER ]] ; then
		echo -e "| *** ${red} Image is not owned by ProjectID: ${PROJECT} ${NC}"
		echo -e "| *** ${lt_brn} Skipping download ${NC}"
		DOWNLOAD=false
	fi

	# Check for existing file; 2nd round pass don't redownload:
	if [[ -f ${DIR}/${FILE_NAME} ]] ; then
		FILE_SIZE=`stat -c%s "${DIR}/${FILE_NAME}"`
		echo "| *** Checking existing file: ${DIR}/${FILE_NAME}"
		echo "| FILE_SIZE= ${FILE_SIZE}"
		echo "| IMAGE_SIZE= ${IMAGE_SIZE}"

		if [[ $FILE_SIZE == $IMAGE_SIZE ]] ; then
			echo -e "| ${lt_grn}+++ IMAGE FILE ALREADY Downloaded; size OK ${NC}"
			echo -e "| ${lt_brn}*** Skipping download ${NC}"
			DOWNLOAD=false
		fi
	fi

	# Download:
	if [[ $DOWNLOAD == true ]] ; then
		if [[ $TEST == "Y" ]] ; then
			echo ""${GLANCE_CMD} image-download --file "${DIR}/${FILE_NAME}" --progress $IMAGE_ID""
		else
			echo -e "| ${lt_grn} IMAGE Download file: ${DIR}/${FILE_NAME} ${NC}"
			echo "| IMAGE Download start: $(date)"
			${GLANCE_CMD} image-download --file "${DIR}/${FILE_NAME}" --progress $IMAGE_ID
			echo "| IMAGE Download end: $(date)"

			# Validate image according to size:
			FILE_SIZE=`stat -c%s "${DIR}/${FILE_NAME}"`
			echo "| *** Checking downloaded file: ${DIR}/${FILE_NAME}"
			echo "| FILE_SIZE= ${FILE_SIZE}"
			echo "| IMAGE_SIZE= ${IMAGE_SIZE}"

			if [[ $FILE_SIZE == $IMAGE_SIZE ]] ; then
				echo -e "| +++ ${lt_grn} IMAGE FILE Downloaded; size OK ${NC}"
			else
				echo -e "| --- ${red} IMAGE FILE Downloaded; size MISMATCH ${NC}"
			fi
		fi
	fi

}

action_vars()
{
	echo "--- Parameters ---"
		echo "TYPE: ${TYPE}"
		echo "PROJECT: ${PROJECT}"
		echo "PROJECT_NAME: ${PROJECT_NAME}"
		echo "DIR: ${DIR}"
}


###############################################################################
###   -------------------------------------------------------------------   ###
###############################################################################

# main() starts here

# Check and load the new_bu user:
#if [[ ! -f $NEW_BU_USER_CRED_FILE ]] ; then
#    echo "ACTION: no new_bu_user FILE found; terminating!!!"
#    exit
#else
	 source $NEW_BU_USER_CRED_FILE
#fi

# Check for input variables:
# this script should be called with (type, projectID)

# Checking number of arguments:
if [ "$#" -ne 2 ] ; then
	echo "ACTION  main: Not enoght arguments... terminating"
	exit
fi

# main argument variables:
TYPE=$1
PROJECT=$2

# Set the user for the current project
get_bu_user
export OS_TENANT_ID=${PROJECT}
export OS_TENANT_NAME=${PROJECT_NAME}

case "$TYPE" in

	instance)
		echo "ACTION: backing up instances for $PROJECT"
		create_snapshots $PROJECT
		;;

	images)
		echo "ACTION: backing up images for $PROJECT"
	download_images $PROJECT
		;;

	test)
		echo "ACTION: testing"
		set_user admin
		add_user_to_project $PROJECT
		show_vars

		DIR="${INSTANCE_DIR}/${PROJECT}_${PROJECT_NAME}"

	set_bu_user

	# Show instances:
	${NOVA_CMD} list --tenant

	# Show action vars:
	action_vars

		set_user admin
		delete_user_from_project $PROJECT
		;;

	**)
		echo  "ACTION  main: bad first argument... terminating"
		exit
		;;

esac





