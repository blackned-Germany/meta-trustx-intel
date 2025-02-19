inherit image_types
inherit kernel-artifact-names

#
# Create an partitioned gyroidos image that can be dd'ed to the boot medium
#


TEST_CERT_DIR = "${TOPDIR}/test_certificates"
SECURE_BOOT_SIGNING_KEY = "${TEST_CERT_DIR}/ssig_subca.key"
SECURE_BOOT_SIGNING_CERT = "${TEST_CERT_DIR}/ssig_subca.cert"


GYROIDOS_KEYTOOL_BOOTPART="${DEPLOY_DIR_IMAGE}/gyroidos_keytoolbootpart"

GYROIDOS_KEYTOOLTMP="${DEPLOY_DIR_IMAGE}/gyroidos_keytooldir"
GYROIDOS_KEYTOOL_IMAGE_OUT="${DEPLOY_DIR_IMAGE}/gyroidos_image"
GYROIDOS_KEYTOOL_IMAGE="${GYROIDOS_KEYTOOL_IMAGE_OUT}/keytoolimage.img"
GYROIDOS_KEYTOOL_PKI_VERSION="1.0-r0"

do_image_gyroidoskeytool[depends] = " \
    parted-native:do_populate_sysroot \
    mtools-native:do_populate_sysroot \
    dosfstools-native:do_populate_sysroot \
    gptfdisk-native:do_populate_sysroot \
    pki-native:do_populate_sysroot \
"

IMAGE_CMD:gyroidoskeytool () {
	if [ -z "${DEPLOY_DIR_IMAGE}" ];then
		bbfatal "Cannot get bitbake variable \"DEPLOY_DIR_IMAGE\""
		exit 1
	fi

	if [ -z "${GYROIDOS_KEYTOOL_BOOTPART}" ];then
		bbfatal "Cannot get bitbake variable \"GYROIDOS_KEYTOOL_BOOTPART\""
		exit 1
	fi

	if [ -z "${MACHINE}" ];then
		bbfatal "Cannot get bitbake variable \"MACHINE\""
		exit 1
	fi

	rm -fr ${GYROIDOS_KEYTOOL_BOOTPART}

	machine_replaced=$(echo "${MACHINE}" | tr "_" "-")

	bbnote "Copying boot partition files to ${GYROIDOS_KEYTOOL_BOOTPART}"

	mkdir -p "${GYROIDOS_KEYTOOL_BOOTPART}/keys/"
	mkdir -p "${GYROIDOS_KEYTOOL_IMAGE_OUT}/"
	mkdir -p "${GYROIDOS_KEYTOOLTMP}/"

	cp --dereference ${TEST_CERT_DIR}/DB.esl ${GYROIDOS_KEYTOOL_BOOTPART}/keys/
	cp --dereference ${TEST_CERT_DIR}/KEK.esl ${GYROIDOS_KEYTOOL_BOOTPART}/keys/
	cp --dereference ${TEST_CERT_DIR}/PK.cer ${GYROIDOS_KEYTOOL_BOOTPART}/keys/
	cp --dereference ${TEST_CERT_DIR}/PK.auth ${GYROIDOS_KEYTOOL_BOOTPART}/keys/
	bbdebug 1 "Boot machine: $machine"

	install -d "${GYROIDOS_KEYTOOL_BOOTPART}/EFI/BOOT/"
	cp --dereference "${TOPDIR}/tmp/work/x86_64-linux/pki-native/${GYROIDOS_KEYTOOL_PKI_VERSION}/recipe-sysroot-native/usr/bin/KeyTool.efi" "${GYROIDOS_KEYTOOL_BOOTPART}/EFI/BOOT/BOOTX64.EFI"

#	# Create boot file system
	bootpart_size_4k="$(du -s --block-size=1024 ${GYROIDOS_KEYTOOL_BOOTPART} | awk '{print $1}')"
	bootpart_size_4k="$(expr $bootpart_size_4k + 5000)"
	bootpart_size_1k="$(expr $bootpart_size_4k '*' 4)"

	gyroidos_bootfs="${GYROIDOS_KEYTOOLTMP}/bootfs.img"

	rm -f "$gyroidos_bootfs"

	mkdosfs -F 16 -n efi -C "$gyroidos_bootfs" "$bootpart_size_1k"


	chmod 644 "$gyroidos_bootfs"

	find "${GYROIDOS_KEYTOOL_BOOTPART}" -maxdepth 1 ! -path . -exec mcopy -s -i "$gyroidos_bootfs" {} "::/" ';'

	bootfs_size_4k="$(du -s --block-size=4096 $gyroidos_bootfs | awk '{print $1}')"
	bootpart_end_4k="$(expr 34 + $bootpart_size_4k + 10000)"
	bootpart_end_bytes="$(expr $bootpart_end_4k '*' 4096)"
	image_size_4k="$(expr $bootpart_end_4k + 4000)"



	#create boot image
	rm -f "${GYROIDOS_KEYTOOL_IMAGE}"
	dd if=/dev/zero of="${GYROIDOS_KEYTOOL_IMAGE}" conv=notrunc,fsync bs=4096 count="$image_size_4k"

	parted -s "${GYROIDOS_KEYTOOL_IMAGE}" unit B --align none mklabel gpt
	parted -s "${GYROIDOS_KEYTOOL_IMAGE}" unit B --align none mkpart primary "139264" "${bootpart_end_bytes}"
	parted -s "${GYROIDOS_KEYTOOL_IMAGE}" set 1 legacy_boot on
	parted -s "${GYROIDOS_KEYTOOL_IMAGE}" set 1 msftdata on
	parted -s "${GYROIDOS_KEYTOOL_IMAGE}" set 1 boot off
	parted -s "${GYROIDOS_KEYTOOL_IMAGE}" set 1 esp off

	#copy boot file system to image
	bbnote "Copying boot filesystem to partition"
	dd if="$gyroidos_bootfs" of="${GYROIDOS_KEYTOOL_IMAGE}" bs=4096 count=$bootfs_size_4k seek="34" conv=notrunc,fsync iflag=sync oflag=sync status=progress
	/bin/sync
	partlayout="$(parted ${GYROIDOS_KEYTOOL_IMAGE} unit B --align none print 2>&1)"
	bbdebug 1 "${partlayout}"
}
