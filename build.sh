# A function to setup github vars
setup () {
	git config --global user.name "$GH_USERNAME"
	git config --global user.email "$GH_USERMAIL"
}

# A function to send message(s) via Telegram's BOT api.
tgm() {
    curl -sX POST https://api.telegram.org/bot"${TOKEN}"/sendMessage \
        -d chat_id="${CHATID}" \
        -d parse_mode=Markdown \
        -d disable_web_page_preview=true \
        -d text="$1" &>/dev/null
}

# A function to send file(s) via Telegram's BOT api.
tgd() {
    MD5=$(md5sum "$1" | cut -d' ' -f1)
    curl -fsSL -X POST -F document=@"$1" https://api.telegram.org/bot"${TOKEN}"/sendDocument \
        -F "chat_id=${CHATID}" \
        -F "parse_mode=Markdown" \
        -F "caption=$2 | *MD5*: \`$MD5\`"
}

# A function to sync recovery sauce
sync () {
	cd $CIRRUS_WORKING_DIR
	mkdir source
	cd source
	repo init -u $MANIFEST -b $MANIFEST_BRANCH --depth=1 --groups=all,-notdefault,-device,-darwin,-x86,-mips
	repo sync -c --no-clone-bundle --no-tags --optimized-fetch --prune --force-sync -j4
	git clone $DT_LINK --depth=1 --single-branch $DT_PATH
	tgm "∆ [ Sync Complete! ] ∆"
}

# A function to build recovery image/zip
build () {
	BUILD_START=$(date +"%s")
	cd $CIRRUS_WORKING_DIR/source
	. build/envsetup.sh
	lunch twrp_$DEVICE-eng
	export ALLOW_MISSING_DEPENDENCIES=true
	mka recoveryimage
	BUILD_END=$(date +"%s")
	export BUILD_TIME=$((BUILD_END - BUILD_START))
 }

# A function to upload recovery image/zip to sourceforge and send a post to channel
success () {
	cd $CIRRUS_WORKING_DIR/source
	tgm "∆ [ Build succeed! Posting in few seconds... ] ∆"

	# Upload
	expect -c "
	spawn sftp $SF_USERNAME@frs.sourceforge.net
	expect \"yes/no\"
	send \"yes\r\"
	expect \"Password\"
	send \"$SF_PASS\r\"
	expect \"sftp> \"
	send \"mkdir '/home/pfs/project/recovery-ci/$DEVICE'\r\"
	set timeout -1
	expect \"sftp>\"
	send \"cd '/home/pfs/project/recovery-ci/$DEVICE'\r\"
	set timeout -1
	send \"put recovery*.zip\r\"
	expect \"Uploading\"
	expect \"100%\"
	expect \"sftp>\"
	send \"bye\r\"
	interact"

	# Post
	tgm "Build completed successfully in $((BUILD_TIME / 60)):$((BUILD_TIME % 60))
	Link: https://sourceforge.net/projects/recovery-ci/files/""$DEVICE""/recovery-""$CIRRUS_BUILD_ID"".zip/download
	      < File will be available to download after a few minutes >
	Dev : ""$GH_USERNAME""
	Product : Recovery
	Device : ""$DEVICE""
	Server Host : cirrus-ci
	Date : ""$(env TZ=Asia/Kolkata date)"""
}

# A function to send failed build log to channel
fail () {
	echo "Uploading error.log!"
	tgd "out/*.log" "\`Build failed in $((BUILD_TIME / 60)):$((BUILD_TIME % 60))\`"
}

# A function to check whether build succeed or failed
check () {
	cd $CIRRUS_WORKING_DIR/source
	mkdir recovery
	if [ -e $OUT_DIRECTORY/*.zip ]; then
		echo "Found $(basename $OUT_DIRECTORY/*.zip)! Uploading!"
		cp $OUT_DIRECTORY/*.zip recovery
		zip -r recovery-$CIRRUS_BUILD_ID.zip recovery
		success
	elif [ $(ls $OUT_DIRECTORY/*.img | wc -l) -gt 3 ]; then
		echo "Packing $(ls $OUT_DIRECTORY/*.img) files!"
		cp $OUT_DIRECTORY/*.img recovery
		zip -r recovery-$CIRRUS_BUILD_ID.zip recovery
		success
	else
		fail
	fi
}

# A function to call all functions one by one in order
main () {
	cd $CIRRUS_WORKING_DIR/source
	setup
	tgm "∆ [ Build Started ] ∆"
	sync
	build
	check
}

main
