#!/bin/bash

temp_dir="dcv_local_sessions_install"
mkdir $temp_dir
cp -a install.sh uninstall.sh ${temp_dir}/
mkdir ${temp_dir}/api/
cp -a api/app.py ${temp_dir}/api/
tar czf ${temp_dir}.tar.gz $temp_dir
rm -rf ${temp_dir}/
