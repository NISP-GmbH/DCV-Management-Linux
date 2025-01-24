#!/bin/bash

temp_dir="dcv_local_sessions_install"
mkdir $temp_dir
cp -a install.sh uninstall.sh dcv_collab_prompt_script.sh dcv_local_sessions.sh config.conf library.sh ${temp_dir}/
mkdir ${temp_dir}/api/
cp -a api/app.py ${temp_dir}/api/
tar czf ${temp_dir}.tar.gz $temp_dir
rm -rf ${temp_dir}/
