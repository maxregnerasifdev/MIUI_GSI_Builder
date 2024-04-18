source ./bin/common_functions.sh

bootclasspath_miui_blacklist=("com.qualcomm.qti.camera.jar" "QPerformance.jar")

prop_locations=("etc/prop.default" "build.prop")

DEBUG=TRUE
TARGET=

POSITIONAL=()
while [[ $# -gt 0 ]]; do
	key="$1"

	case $key in
		-t|--target)
		TARGET="$2"
		shift
		shift
		;;
		user)
		DEBUG=FALSE
		shift
		;;
		testmode)
		TESTMODE=TRUE
		shift
		;;
		*)
		POSITIONAL+=("$1")
		shift
		;;
	esac
done
set -- "${POSITIONAL[@]}"

echo ""
if [ "${TARGET}" != "ab" -a "${TARGET}" != "a" ]; then
	echo "[i] Usage for 01_make_target_from_src.sh:"
	echo "    -t|--target ab|a"
	echo "    [user]"
	echo "    [testmode]"
	echo ""
	exit -1
fi

if [ "${DEBUG}" == "FALSE" ]; then
	echo "[!] User build requested but currently unsupported."
	echo ""
	exit -1
fi

if [ "${TARGET}" == "ab" ]; then
	SRC_GSI_SYSTEM="system"
fi

if [ "${TARGET}" == "a" ]; then
	SRC_GSI_SYSTEM="."
fi

if [ "${SRC_GSI_SYSTEM}" == "" ]; then
	echo "[!] Unsupported target type requested - '${TARGET}'"
	echo ""
	exit -1
fi

echo ""
echo "------------------------------------------"
echo "[i] 01_make_target_from_src started."
echo ""

if [ -d "./target_system" -a "${TESTMODE}" != "TRUE" ]; then
	echo "[!] A ./target_system/ folder exists."
	echo "    Aborting for safety reasons."
	exit -1
fi

if [ "${TESTMODE}" == "TRUE" ]; then
	echo "[i] Testmode enabled. Will only copy the bulk of GSI/MIUI files if target_system does not exist."
fi

checkAndMakeTmp

echo "[#] Creating GSI with MIUI replaced /system..."
mkdir "./target_system"
if [ "${TESTMODE}" != "TRUE" -o ! -d "./target_system" ]; then
	rsync -a --exclude 'system' "./src_gsi_system/" "./target_system/"
	rsync -a "src_miui_system/" "target_system/${SRC_GSI_SYSTEM}/"
	echo "[#] Replacing selinux with GSI..."
	rm -rf "./target_system/${SRC_GSI_SYSTEM}/etc/selinux/*"
	rsync -a "./src_gsi_system/system/etc/selinux/" "./target_system/${SRC_GSI_SYSTEM}/etc/selinux/"
fi

if [ "${DEBUG}" == "TRUE" ]; then
	echo "[#] Insecure/root-mode ADBD patch..."
	if [ "${TARGET}" == "ab" ]; then
		sed -i --follow-symlinks 's|ro.adb.secure=.*|ro.adb.secure=0|g' "./target_system/${SRC_GSI_SYSTEM}/etc/prop.default"
		sed -i --follow-symlinks 's|ro.debuggable=.*|ro.debuggable=1|g' "./target_system/${SRC_GSI_SYSTEM}/etc/prop.default"
		sed -i --follow-symlinks 's|persist.sys.usb.config=.*|persist.sys.usb.config=adb|g' "./target_system/${SRC_GSI_SYSTEM}/etc/prop.default"
	fi
	sed -i --follow-symlinks 's|ro.adb.secure=.*|ro.adb.secure=0|' "./target_system/${SRC_GSI_SYSTEM}/build.prop"
	cp -af "./target_patches/adbd_godmode" "./target_system/${SRC_GSI_SYSTEM}/bin/adbd"
fi

echo "[#] Init changes..."
verifyFilesExist "./src_miui_initramfs/init.miui.rc"
cp -af ./src_miui_initramfs/init.miui.rc ./target_system/${SRC_GSI_SYSTEM}/etc/init/init.miui.rc

echo "    [#] Parsing MIUI BOOTCLASSPATH..."
bootclasspath=`cat ./src_miui_initramfs/init.environ.rc | grep -i 'export BOOTCLASSPATH ' | sed 's|^[ \t]*export BOOTCLASSPATH[ \t]*||'`
IFS=':' read -r -a bootclasspath_array <<< "${bootclasspath}"
bootclasspath=""
for bootclasspath_entry in "${bootclasspath_array[@]}"; do	
	skip=false
	for blacklist_entry in "${bootclasspath_miui_blacklist[@]}"; do
		if [ ! "${bootclasspath_entry/$blacklist_entry}" == "${bootclasspath_entry}" ] ; then
			targetJarPath="./target_system`echo ${bootclasspath_entry} | sed 's|/system/|'/${SRC_GSI_SYSTEM}/'|'`"
			rm -f ${targetJarPath}
			echo "        [i] Removed blacklisted entry and associated file: ${bootclasspath_entry}"
			skip=true
		fi
	done
	if [ "${skip}" == "false" ]; then
		if [ "${bootclasspath}" == "" ]; then
			bootclasspath="${bootclasspath_entry}"
		else
			bootclasspath="${bootclasspath}:${bootclasspath_entry}"
		fi
	fi
done

systemserverclasspath=`cat ./src_miui_initramfs/init.environ.rc | grep -i 'export SYSTEMSERVERCLASSPATH ' | sed 's|^[ \t]*export SYSTEMSERVERCLASSPATH[ \t]*||'`
echo "# Treble-adjusted values for MIUI GSI" > ./target_system/${SRC_GSI_SYSTEM}/etc/init/init.treble-environ.rc
cat <<EOF >>./target_system/${SRC_GSI_SYSTEM}/etc/init/init.treble-environ.rc
on init
    export BOOTCLASSPATH ${bootclasspath}
    export SYSTEMSERVERCLASSPATH ${systemserverclasspath}
EOF
echo "    [i] Wrote BOOTCLASSPATH and SYSTEMSERVERCLASSPATH to init.treble-environ.rc"

echo "[#] Building SELinux policy..."
cat "./src_miui_system/etc/selinux/plat_file_contexts" "./src_gsi_system/${SRC_GSI_SYSTEM}/etc/selinux/plat_file_contexts" > "./tmp/plat_file_contexts_joined"
sort -u -k1,1 "./tmp/plat_file_contexts_joined" > "./target_system/${SRC_GSI_SYSTEM}/etc/selinux/plat_file_contexts"
cat "./src_miui_system/etc/selinux/plat_property_contexts" "./src_gsi_system/${SRC_GSI_SYSTEM}/etc/selinux/plat_property_contexts" > "./tmp/plat_property_contexts_joined"
sort -u -k1,1 "./tmp/plat_property_contexts_joined" > "./target_system/${SRC_GSI_SYSTEM}/etc/selinux/plat_property_contexts"
cp -af "./src_miui_system/etc/selinux/plat_seapp_contexts" "./target_system/${SRC_GSI_SYSTEM}/etc/selinux/plat_seapp_contexts"
cat "./src_miui_system/etc/selinux/plat_service_contexts" "./src_gsi_system/${SRC_GSI_SYSTEM}/etc/selinux/plat_service_contexts" > "./tmp/plat_service_contexts_joined"
sort -u -k1,1 "./tmp/plat_service_contexts_joined" > "./target_system/${SRC_GSI_SYSTEM}/etc/selinux/plat_service_contexts"

echo "    [#] Scanning for missing/orphaned init service SELinux labels..."
for rcFile in "./target_system/${SRC_GSI_SYSTEM}/etc/init"/*; do
	rm -f "./tmp/rcFileNew"
	cp -af "${rcFile}" "./tmp/rcFileOld"
	printf "\n\n" >> "./tmp/rcFileOld"
	cat "./tmp/rcFileOld" | while read -r LINE; do
		if [[ "$(echo "${LINE}" | awk '{ print $1 }')" == "service" ]]; then
			servicePath="`echo "${LINE}" | awk '{ print $3 }'`"
			serviceName="`echo "${LINE}" | awk '{ print $2 }'`"
			echo "${LINE}" >> "./tmp/rcFileNew"
		elif [ "${servicePath}" != "" ]; then
			if [[ "$(echo "${LINE}" | awk '{ print $1 }')" == "seclabel" ]]; then
				seclabel="${LINE}"
			elif [ "${LINE}" == "" ]; then
				if [ "${seclabel}" == "" ]; then
					servicePathEscaped=${servicePath//./\\\\\.}
					seclabel=`cat "./src_gsi_system/${SRC_GSI_SYSTEM}/etc/selinux/plat_file_contexts" | grep "^${servicePathEscaped}" | awk '{ print $2 }'`
				fi
				mappingExists=FALSE
				if [ "${seclabel}" != "" ]; then
					mappingToken="`echo "${seclabel}" | awk -F":" '{print $3}'`"
					if grep -q '^(typeattributeset .*(.*'${mappingToken}'.*))' "./target_system/${SRC_GSI_SYSTEM}/etc/selinux/mapping/27.0.cil"; then
						mappingExists=TRUE
					elif grep -q '^(typeattributeset .*(.*'${mappingToken}'.*))' "./target_system/${SRC_GSI_SYSTEM}/etc/selinux/plat_sepolicy.cil"; then
						mappingExists=TRUE
					fi
				fi
				if [ "${mappingExists}" == "FALSE" ]; then
					seclabel="seclabel u:r:shell:s0"
					echo "    ${seclabel}" >> "./tmp/rcFileNew"
					echo "      [i] Added/replaced seclabel for ${serviceName}"
				fi
				echo "" >> "./tmp/rcFileNew"
				serviceName=""
				servicePath=""
				mappingToken=""
				seclabel=""
			else
				echo "${LINE}" >> "./tmp/rcFileNew"
			fi
		else
			echo "${LINE}" >> "./tmp/rcFileNew"
		fi
	done
	cp -af "./tmp/rcFileNew" "${rcFile}"
done

echo "[#] Generification..."
echo "    [#] Removing vendor-specific files..."

removeFromTarget \
	app/CarrierConfigure \
	app/CtRoamingSettings \
	app/SnapdragonSVA \
	app/seccamsample \
	etc/audio_policy.conf \
	etc/vold.fstab \
	etc/bluetooth/bt_profile.conf \
	etc/bluetooth/interop_database.conf \
	etc/init/init.qti.fm.rc \
	etc/permissions/qti_permissions.xml \
	lib/egl \
	lib64/egl \
	lib/modules \
	lib/rfsa \
	lib/android.hardware.biometrics.fingerprint@*.so \
	lib64/android.hardware.biometrics.fingerprint@*.so \
	lib/android.hardware.health@*.so \
	lib/android.hardware.radio.deprecated@*.so \
	lib64/android.hardware.radio.deprecated@*.so \
	lib/android.hardware.radio@*.so \
	lib64/android.hardware.radio@*.so \
	lib/android.hidl.base@*.so \
	lib64/android.hidl.base@*.so \
	lib/com.qualcomm.qti.*.so \
	lib64/com.qualcomm.qti.*.so \
	lib/vendor.qti.*.so \
	lib64/vendor.qti.*.so \
	lib/vndk-sp/android.hidl.base@*.so \
	lib64/vndk-sp/android.hidl.base@*.so \
	lib/libsensor1.so \
	lib/libsensor_reg.so \
	lib64/libsensor1.so \
	lib64/libsensor_reg.so \
	lib64/android.hardware.wifi.supplicant@*.so \
	lib64/android.hardware.wifi@*.so \
	priv-app/cit \
	priv-app/AutoTest \
	usr/

removeFromTarget \
	bin/dpmd \
	etc/init/dpmd.rc \
	app/QtiTelephonyService \
	etc/permissions/telephonyservice.xml \
	framework/QtiTelephonyServicelibrary.jar

removeFromTarget \
	lib/liblocationservice_jni.so \
	lib64/liblocationservice_jni.so \
	lib/libxt_native.so \
	lib64/libxt_native.so \
	priv-app/com.qualcomm.location

echo "    [#] Copying unique GSI files..."
rsync -a --ignore-existing "./src_gsi_system/system/bin/" "./target_system/${SRC_GSI_SYSTEM}/bin/"
rsync -a --ignore-existing "./src_gsi_system/system/etc/" "./target_system/${SRC_GSI_SYSTEM}/etc/"
rsync -a --ignore-existing "./src_gsi_system/system/lib/" "./target_system/${SRC_GSI_SYSTEM}/lib/"
rsync -a --ignore-existing "./src_gsi_system/system/lib64/" "./target_system/${SRC_GSI_SYSTEM}/lib64/"
rsync -a --ignore-existing "./src_gsi_system/system/phh/" "./target_system/${SRC_GSI_SYSTEM}/phh/"
rsync -a --ignore-existing "./src_gsi_system/system/usr/" "./target_system/${SRC_GSI_SYSTEM}/usr/"
rsync -a --ignore-existing "./src_gsi_system/system/xbin/" "./target_system/${SRC_GSI_SYSTEM}/xbin/"

addToTargetFromGsi \
	compatibility_matrix.xml \
	bin/keystore \
	etc/bluetooth/bt_did.conf \
	etc/init/audioserver.rc \
	etc/init/bootanim.rc

mv "./target_system/${SRC_GSI_SYSTEM}/bin/cameraserver" "./target_system/${SRC_GSI_SYSTEM}/bin/cameraserver_disabled"

if [ "${TARGET}" == "ab" ]; then
	addToTargetFromGsi \
		bin/bootctl
fi

echo "[#] Adding/updating props ..."
{
IFS=
echo "" >> "./target_system/${SRC_GSI_SYSTEM}/${prop_locations[0]}"
echo "######" >> "./target_system/${SRC_GSI_SYSTEM}/${prop_locations[0]}"
echo "# Additional for MIUI GSI" >> "./target_system/${SRC_GSI_SYSTEM}/${prop_locations[0]}"
echo "######" >> "./target_system/${SRC_GSI_SYSTEM}/${prop_locations[0]}"
echo "" >> "./target_system/${SRC_GSI_SYSTEM}/${prop_locations[0]}"

echo "    [#] Removing specific props..."
if [ -f "./target_patches/props.remove" ]; then
	sed '/^[ \t]*$/d' "./target_patches/props.remove" | while read -r LINE; do
		if [[ "${LINE}" == "#"* ]]; then
			continue
		fi
		propKey="${LINE%=*}="
		addOrReplaceTargetProp "${propKey}"
	done
fi

echo "    [#] Additional custom props..."
if [ -f "./target_patches/props.additional" ]; then
	sed '/^[ \t]*$/d' "./target_patches/props.additional" | while read -r LINE; do
		if [[ "${LINE}" == "#"* ]]; then
			continue
		fi
		propKey="${LINE%=*}="
		addOrReplaceTargetProp "${propKey}" "${LINE}"
	done
fi

echo "    [#] GSI-sourced props..."
if [ -f "./target_patches/props.merge" ]; then
	sed '/^[ \t]*$/d' "./target_patches/props.merge" | while read -r LINE; do
		if [[ "${LINE}" == "#"* ]]; then
			continue
		fi
		propKey="${LINE%=*}="
		for propFile in "${prop_locations[@]}"; do
			propSearch=`grep ${propKey} "./src_gsi_system/${SRC_GSI_SYSTEM}/${propFile}"`
			if [ "${propSearch}" != "" ]; then
				propFound="${propSearch}"
			fi
		done
		if [ "${propFound}" == "" ]; then
			echo "[!] Error - cannot find prop from GSI with key: ${propKey}"
			echo "    Aborted."
			exit -1
		else
			addOrReplaceTargetProp "${propKey}" "${propFound}"
			propFound=""
		fi
	done
fi
}

echo "[#] Misc. fixups..."

echo ""
echo "[i] 01_make_target_from_src finished."
echo "------------------------------------------"

cleanupTmp
