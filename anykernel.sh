# AnyKernel 2.0 Ramdisk Mod Script 
# osm0sis @ xda-developers

## AnyKernel setup
# EDIFY properties
kernel.string=Render Kernel by RenderBroken!
do.devicecheck=0
do.initd=1
do.modules=1
do.cleanup=0
device.name1=victara
device.name2=
device.name3=
device.name4=
device.name5=

# shell variables
block=/dev/block/platform/msm_sdcc.1/by-name/boot;
initd=/system/etc/init.d;
bindir=/system/bin;
## end setup


## AnyKernel methods (DO NOT CHANGE)
# set up extracted files and directories
ramdisk=/tmp/anykernel/ramdisk;
bin=/tmp/anykernel/tools;
split_img=/tmp/anykernel/split_img;
patch=/tmp/anykernel/patch;

chmod -R 755 $bin;
mkdir -p $ramdisk $split_img;
cd $ramdisk;

OUTFD=`ps | grep -v "grep" | grep -oE "update(.*)" | cut -d" " -f3`;
ui_print() { echo "ui_print $1" >&$OUTFD; echo "ui_print" >&$OUTFD; }

# dump boot and extract ramdisk
dump_boot() {
  dd if=$block of=/tmp/anykernel/boot.img;
  $bin/unpackbootimg -i /tmp/anykernel/boot.img -o $split_img;
  if [ $? != 0 ]; then
    ui_print " "; ui_print "Dumping/unpacking image failed. Aborting...";
    echo 1 > /tmp/anykernel/exitcode; exit;
  fi;
  gunzip -c $split_img/boot.img-ramdisk.gz | cpio -i;
}

# repack ramdisk then build and write image
write_boot() {
  cd $split_img;
  cmdline=`cat *-cmdline`;
  board=`cat *-board`;
  base=`cat *-base`;
  pagesize=`cat *-pagesize`;
  kerneloff=`cat *-kerneloff`;
  ramdiskoff=`cat *-ramdiskoff`;
  tagsoff=`cat *-tagsoff`;
  if [ -f *-second ]; then
    second=`ls *-second`;
    second="--second $split_img/$second";
    secondoff=`cat *-secondoff`;
    secondoff="--second_offset $secondoff";
  fi;
  if [ -f /tmp/anykernel/dtb ]; then
    dtb="--dt /tmp/anykernel/dtb";
  elif [ -f *-dtb ]; then
    dtb=`ls *-dtb`;
    dtb="--dt $split_img/$dtb";
  fi;
  cd $ramdisk;
  find . | cpio -H newc -o | gzip > /tmp/anykernel/ramdisk-new.cpio.gz;
  $bin/mkbootimg --kernel /tmp/anykernel/zImage --ramdisk /tmp/anykernel/ramdisk-new.cpio.gz $second --cmdline "$cmdline" --board "$board" --base $base --pagesize $pagesize --kernel_offset $kerneloff --ramdisk_offset $ramdiskoff $secondoff --tags_offset $tagsoff $dtb --output /tmp/anykernel/boot-new.img;
  if [ $? != 0 -o `wc -c < /tmp/anykernel/boot-new.img` -gt `wc -c < /tmp/anykernel/boot.img` ]; then
    ui_print " "; ui_print "Repacking image failed. Aborting...";
    echo 1 > /tmp/anykernel/exitcode; exit;
  fi;
  dd if=/tmp/anykernel/boot-new.img of=$block;
}

# backup_file <file>
backup_file() { cp $1 $1~; }

# replace_string <file> <if search string> <original string> <replacement string>
replace_string() {
  if [ -z "$(grep "$2" $1)" ]; then
      sed -i "s;${3};${4};" $1;
  fi;
}

# insert_line <file> <if search string> <before/after> <line match string> <inserted line>
insert_line() {
  if [ -z "$(grep "$2" $1)" ]; then
    case $3 in
      before) offset=0;;
      after) offset=1;;
    esac;
    line=$((`grep -n "$4" $1 | cut -d: -f1` + offset));
    sed -i "${line}s;^;${5};" $1;
  fi;
}

# replace_line <file> <line replace string> <replacement line>
replace_line() {
  if [ ! -z "$(grep "$2" $1)" ]; then
    line=`grep -n "$2" $1 | cut -d: -f1`;
    sed -i "${line}s;.*;${3};" $1;
  fi;
}

# remove_line <file> <line match string>
remove_line() {
  if [ ! -z "$(grep "$2" $1)" ]; then
    line=`grep -n "$2" $1 | cut -d: -f1`;
    sed -i "${line}d" $1;
  fi;
}

# prepend_file <file> <if search string> <patch file>
prepend_file() {
  if [ -z "$(grep "$2" $1)" ]; then
    echo "$(cat $patch/$3 $1)" > $1;
  fi;
}

# append_file <file> <if search string> <patch file>
append_file() {
  if [ -z "$(grep "$2" $1)" ]; then
    echo -ne "\n" >> $1;
    cat $patch/$3 >> $1;
    echo -ne "\n" >> $1;
  fi;
}

# replace_file <file> <permissions> <patch file>
replace_file() {
  cp -fp $patch/$3 $1;
  chmod $2 $1;
}

## end methods


## AnyKernel permissions
# set permissions for included files
chmod -R 755 $ramdisk
#chmod 644 $ramdisk/sbin/media_profiles.xml

## AnyKernel install
dump_boot;

# begin ramdisk changes

# insert initd scripts
cp -fp $patch/init.d/* $initd
chmod -R 766 $initd

# mpdecsion binary
mv $bindir/mpdecision-rm $bindir/mpdecision

# adb secure
backup_file default.prop;
replace_string default.prop "ro.adb.secure=0" "ro.adb.secure=1" "ro.adb.secure=0";
replace_string default.prop "ro.secure=0" "ro.secure=1" "ro.secure=0";

# init.mmi.rc
backup_file init.mmi.rc;
append_file init.mmi.rc "render-post_boot" init.mmi.patch;

# panel and gamma
#backup_file init.qcom-common.rc
#replace_line init.qcom-common.rc "chown system graphics /sys/devices/virtual/graphics/fb0/panel_calibration" "    chown system system /sys/devices/virtual/graphics/fb0/panel_calibration";

# add frandom compatibility
#backup_file ueventd.rc;
#insert_line ueventd.rc "frandom" after "urandom" "/dev/frandom              0666   root       root\n";
#insert_line ueventd.rc "erandom" after "urandom" "/dev/erandom              0666   root       root\n";

#backup_file file_contexts;
#insert_line file_contexts "frandom" after "urandom" "/dev/frandom				u:object_r:frandom_device:s0\n";
#insert_line file_contexts "erandom" after "urandom" "/dev/erandom				u:object_r:erandom_device:s0\n";

# Add F2FS Support for /data and /cache since its can be used on ANY rom
#backup_file fstab.bacon
#replace_file fstab.bacon 750 fstab.bacon;

# xPrivacy
# Thanks to @Shadowghoster & @@laufersteppenwolf
param=$(grep "xprivacy" service_contexts)
if [ -z $param ]; then
    echo -ne "xprivacy453                               u:object_r:system_server_service:s0\n" >> service_contexts
fi

# end ramdisk changes

write_boot;

## end install

