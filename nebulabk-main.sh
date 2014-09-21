#!/bin/bash

# Include Global vars and functions:
source nebulabk-global.sh

###############################################################################
###   -------------------------------------------------------------------   ###
###############################################################################

snapshot_trigger()
{
    # Create bu user:
    set_user admin
    create_bu_user

    if [[ $1 = "all" ]] ; then
	# step through all the projects that are enabled, and d/l  the images owned by that project
	local LIST=`${KEYSTONE_CMD}  tenant-list | sed -n '4,$ p' | sed -n '$! p' | sed "s/ //g" | grep True | grep -v ${NEW_BU_OS_TENANT_ID} | awk -F\| '{ print $2 }'`
	#local LIST=$TEST_LIST # testing
	echo "+-------------- Step through the Projects, Snapshot and Download the Instances -------------+"
	echo "Full trigger not yet enabled"
    elif [[ $1 = "project" ]] ; then
	echo "+----------------------- Snapshot and back up Project Instances ------------------------+"
	${KEYSTONE_CMD} tenant-list
	echo -e "${lt_blue} Choose tenant (project) ID from list above${NC}"
	read PROJ
	local LIST=$PROJ
    fi

    echo "+---------------------------- Snapshot and Backup Instances in Parallel ---------------------------+"
    #parallel -j $TENANT_JOBS ./echo-test.sh  instance {1} ::: $LIST
    #parallel -j $TENANT_JOBS ./nebulabk-action.sh test {1} ::: $LIST
    parallel -j $TENANT_JOBS ./nebulabk-action.sh  instance {1} ::: $LIST

    # Delete bu user:
    set_user admin
    delete_bu_user

}

###############################################################################
###   -------------------------------------------------------------------   ###
###############################################################################

image_trigger()
{
    # Create bu user:
    set_user admin
    create_bu_user

    if [[ $1 = "all" ]] ; then
	# step through all the projects that are enabled, and d/l  the images owned by that project
	local LIST=`${KEYSTONE_CMD}  tenant-list | sed -n '4,$ p' | sed -n '$! p' | sed "s/ //g" | grep True | grep -v ${NEW_BU_OS_TENANT_ID} | awk -F\| '{ print $2 }'`
	#local LIST=$TEST_LIST # testing
	echo "+-------------- Step through ALL Projects, Snapshot and Download the Instances -------------+"
    elif [[ $1 = "project" ]] ; then
	echo "+----------------------- Snapshot and back up Project Instances ------------------------+"
	${KEYSTONE_CMD} tenant-list
	echo -e "${lt_blue} Choose tenant (project) ID from list above${NC}"
	read PROJ
	local LIST=$PROJ
    fi

    echo "+---------------------------- Snapshot and Backup Instances in Parallel ---------------------------+"
    #parallel -j $TENANT_JOBS ./echo-test.sh  instance {1} ::: $LIST
    #parallel -j $TENANT_JOBS ./nebulabk-action.sh test {1} ::: $LIST
    parallel -j $TENANT_JOBS ./nebulabk-action.sh  images {1} ::: $LIST

    # Delete bu user:
    set_user admin
    delete_bu_user

}

###############################################################################
###   -------------------------------------------------------------------   ###
###############################################################################

# main() starts here

tempfile="cmd.done"
touch ${tempfile}

case "${OS_COLOR}" in
	linux)
		# Linux Colors
		red='\e[0;31m'
		lt_brn='\e[0;33m'
		lt_blue='\e[1;34m'
		lt_grn='\e[1;32m'
		NC='\e[0m' # No Color
		;;
	mac_os)
		# MAC OS Colors
		red='\x1B[0;31m'
		lt_brn='\x1B[1;33m'
		lt_blue='\x1B[1;34m'
		lt_grn='\x1B[1;32m'
		NC='\x1B[0m' # No Color
		;;
esac

set_user
roles

### Continue while cmd.done file is not there

while [ -f ${tempfile} ]; do

	echo
	if [[ ${TEST} == "Y" ]] ; then
		echo -e "${red} --- TEST Mode Set --- ${NC}"
	else
		echo -e "${lt_grn} --- Save Image Mode Set --- ${NC}"
	fi
	echo -e "${lt_blue} --------------------- "
	echo " Execute the following "
	echo -e " --------------------- ${NC}"
	echo " Enter Option <0,1,2a,2b,3a,...>"
	echo " 0) Exit"
	echo " 1) show user credentials"
	echo " 2) glance commands"
	echo "     a) image list"
	echo "     b) image list by project"
	echo " 3) keystone commands"
	echo "     a) list endpoint"
	echo "     b) list role"
 	echo "     c) list service"
 	echo "     d) list tenant (project)"
 	echo "     e) list user"
	echo " 4) nova commands"
	echo "     a) list instances"
	echo " 5) swift list"
	echo " 6) backup"
	echo "     a) backup all Nebula Controller tenant (project) images"
	echo "     b) backup tenant (project) images"
	echo " 7) create snapshots for backups"
	echo "     a) snapshot all Nebula Controller tenant (project) instances"
	echo "     b) backup tenant (project) instances"
	echo " 8) swich users"
 	echo " 9) Backup user admin"
	echo "     a) Show bu user"
	echo "     b) add bu user"
	echo "     c) delete bu user"
	echo

	read OPTION

	case "${OPTION}" in
	0)
		exit
		rm $tempfile
		;;
	1)
		show_credentials
		;;
	2a)
		${GLANCE_CMD} image-list
		;;
	2b)
		${GLANCE_CMD} image-list
		;;
	3a)
		${KEYSTONE_CMD} endpoint-list
		;;
	3b)
		${KEYSTONE_CMD} role-list
		;;
	3c)
		${KEYSTONE_CMD} service-list
		;;
	3d)
		${KEYSTONE_CMD} tenant-list
		;;
	3e)
		${KEYSTONE_CMD} user-list
		;;
	4a)
		${NOVA_CMD} list --all-tenants
		;;
	5)
		${SWIFT_CMD} list
		;;
	6a)
		image_trigger all
		;;
	6b)
		image_trigger project
		;;
	7a)	snapshot_trigger all
		;;
	7b)	snapshot_trigger project
		;;
	8)
		set_user
		;;
	9a)
		show_bu_user
		;;
	9b)
		create_bu_user
		;;

	9c)
		delete_bu_user
		;;

	10)
		env | grep OS_
		;;

	11)
		env
		show_vars
		;;

	*)
		rm ${tempfile}
		exit
		;;
	esac
done


