#!/bin/bash
# Generate new certificates for 10 years
# Kubeadm generates certificates by default for 1 years
# Optimized for Kubernetes Version 1.9.4
# Tested with Kubernetes Versions 1.8.0 - 1.9.4
# Written by Rick

MASTER_HOSTNAME="$(hostname)"
POD_CIDR="0.0.0.0"
MASTER_IP="0.0.0.0"

function stop_kubelet {
 systemctl stop kubelet
 sleep 15
}

function create_directories {
#Sort Folders for Rick's OCD
cd /etc/kubernetes/pki
mkdir -p usvc-backup-certs
mkdir -p usvc-users

#Create this folder to generate kubedev certs for Development Authorization
mkdir -p usvc-users/kubedev

#Default Roles by Master
mkdir -p usvc-users/admin
mkdir -p usvc-users/controller-manager
mkdir -p usvc-users/kubelet
mkdir -p usvc-users/scheduler
}

function backup_certificates {
cp -p apiserver.key apiserver.key.bk
cp -p apiserver.crt apiserver.crt.bk
cp -p ca.key ca.key.bk
cp -p ca.crt ca.crt.bk
cp -p apiserver-kubelet-client.crt apiserver-kubelet-client.crt.bk
cp -p apiserver-kubelet-client.key apiserver-kubelet-client.key.bk
cp -p front-proxy-ca.crt front-proxy-ca.crt.bk
cp -p front-proxy-ca.key front-proxy-ca.key.bk
cp -p front-proxy-client.crt front-proxy-client.crt.bk
cp -p front-proxy-client.key front-proxy-client.key.bk
mv *.bk /etc/kubernetes/pki/usvc-backup-certs
}

function configure_v3_ca_certs {
  cat <<-EOF_api-ext > /etc/kubernetes/pki/usvc-users/api-ext.cnf
 [ v3_ca ]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName          = @alternate_names
[ alternate_names ]
DNS.1           = $MASTER_HOSTNAME
DNS.2           = kubernetes
DNS.3           = kubernetes.default
DNS.4           = kubernetes.default.svc
DNS.5           = kubernetes.default.svc.cluster.local
IP.1            = $POD_CIDR
IP.2            = $MASTER_IP
EOF_api-ext

cat <<-'EOF_default-ext' > /etc/kubernetes/pki/usvc-users/default-ext.cnf
 [ v3_ca ]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
EOF_default-ext

cat <<-'EOF_fpca-ext' > /etc/kubernetes/pki/usvc-users/fpca-ext.cnf
 [ v3_ca ]
keyUsage = critical, digitalSignature, keyEncipherment
basicConstraints = critical, CA:TRUE
EOF_fpca-ext
}

function generate_certificates {
cd /etc/kubernetes/pki
openssl req -new -key apiserver.key -out apiserver.csr -subj "/CN=kube-apiserver"
openssl x509 -req -in apiserver.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -sha256 -out apiserver.crt -extensions v3_ca -extfile /etc/kubernetes/pki/usvc-users/api-ext.cnf -days 3650

openssl req -new -key apiserver-kubelet-client.key -out apiserver-kubelet-client.csr -subj "/O=system:masters/CN=kube-apiserver-kubelet-client"
openssl x509 -req -in apiserver-kubelet-client.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -sha256 -out apiserver-kubelet-client.crt -extensions v3_ca -extfile /etc/kubernetes/pki/usvc-users/default-ext.cnf -days 3650

openssl req -new -key front-proxy-ca.key -out front-proxy-ca.csr -subj "/CN=kubernetes"
openssl x509 -req -in front-proxy-ca.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -sha256 -out front-proxy-ca.crt -extensions v3_ca -extfile /etc/kubernetes/pki/usvc-users/fpca-ext.cnf -days 3650

openssl req -new -key front-proxy-client.key -out front-proxy-client.csr -subj "/CN=front-proxy-client"
openssl x509 -req -in front-proxy-client.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -sha256 -out front-proxy-client.crt -extensions v3_ca -extfile /etc/kubernetes/pki/usvc-users/default-ext.cnf -days 3650

cd /etc/kubernetes/pki/usvc-users/admin
openssl genrsa -out admin.key 2048
openssl req -new -key admin.key -out admin.csr -subj "/O=system:masters/CN=kubernetes-admin"
openssl x509 -req -in admin.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -sha256 -out admin.crt -extensions v3_ca -extfile /etc/kubernetes/pki/usvc-users/default-ext.cnf -days 3650
base64 admin.crt > admin-crt-data
sed -i \
   -e ':a;N;$!ba;s/\n//g' admin-crt-data
base64 admin.key > admin-key-data
sed -i \
   -e ':a;N;$!ba;s/\n//g' admin-key-data

cd /etc/kubernetes/pki/usvc-users/kubelet
openssl genrsa -out kubelet.key 2048
openssl req -new -key kubelet.key -out kubelet.csr -subj "/O=system:nodes/CN=system:node:$MASTER_HOSTNAME"
openssl x509 -req -in kubelet.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -sha256 -out kubelet.crt -extensions v3_ca -extfile /etc/kubernetes/pki/usvc-users/default-ext.cnf -days 3650
base64 kubelet.crt > kubelet-crt-data
sed -i \
   -e ':a;N;$!ba;s/\n//g' kubelet-crt-data
base64 kubelet.key > kubelet-key-data
sed -i \
   -e ':a;N;$!ba;s/\n//g' kubelet-key-data
cp -p kubelet.key /var/lib/kubelet/pki
cp -p kubelet.crt /var/lib/kubelet/pki

cd /etc/kubernetes/pki/usvc-users/controller-manager
openssl genrsa -out controller-manager.key 2048
openssl req -new -key controller-manager.key -out controller-manager.csr -subj "/CN=system:kube-controller-manager"
openssl x509 -req -in controller-manager.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -sha256 -out controller-manager.crt -extensions v3_ca -extfile /etc/kubernetes/pki/usvc-users/default-ext.cnf -days 3650
base64 controller-manager.crt > controller-manager-crt-data
sed -i \
   -e ':a;N;$!ba;s/\n//g' controller-manager-crt-data
base64 controller-manager.key > controller-manager-key-data
sed -i \
   -e ':a;N;$!ba;s/\n//g' controller-manager-key-data

cd /etc/kubernetes/pki/usvc-users/scheduler
openssl genrsa -out scheduler.key 2048
openssl req -new -key scheduler.key -out scheduler.csr -subj "/CN=system:kube-scheduler"
openssl x509 -req -in scheduler.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -sha256 -out scheduler.crt -extensions v3_ca -extfile /etc/kubernetes/pki/usvc-users/default-ext.cnf -days 3650
base64 scheduler.crt > scheduler-crt-data
sed -i \
   -e ':a;N;$!ba;s/\n//g' scheduler-crt-data
base64 scheduler.key > scheduler-key-data
sed -i \
   -e ':a;N;$!ba;s/\n//g' scheduler-key-data

cd /etc/kubernetes/pki/usvc-users/kubedev
openssl genrsa -out kubedev.key 2048
openssl req -new -key kubedev.key -out kubedev.csr -subj "/CN=kubedev"
openssl x509 -req -in kubedev.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -sha256 -out kubedev.crt -extensions v3_ca -extfile /etc/kubernetes/pki/usvc-users/default-ext.cnf -days 3650
base64 kubedev.crt > kubedev-crt-data
sed -i \
   -e ':a;N;$!ba;s/\n//g' kubedev-crt-data
base64 kubedev.key > kubedev-key-data
sed -i \
   -e ':a;N;$!ba;s/\n//g' kubedev-key-data
}

function configure_conf_files {
ADMIN_CRT_DATA=$(cat /etc/kubernetes/pki/usvc-users/admin/admin-crt-data)
ADMIN_KEY_DATA=$(cat /etc/kubernetes/pki/usvc-users/admin/admin-key-data)
KUBELET_CRT_DATA=$(cat /etc/kubernetes/pki/usvc-users/kubelet/kubelet-crt-data)
KUBELET_KEY_DATA=$(cat /etc/kubernetes/pki/usvc-users/kubelet/kubelet-key-data)
CONTROLLER_CRT_DATA=$(cat /etc/kubernetes/pki/usvc-users/controller-manager/controller-manager-crt-data)
CONTROLLER_KEY_DATA=$(cat /etc/kubernetes/pki/usvc-users/controller-manager/controller-manager-key-data)
SCHEDULER_CRT_DATA=$(cat /etc/kubernetes/pki/usvc-users/scheduler/scheduler-crt-data)
SCHEDULER_KEY_DATA=$(cat /etc/kubernetes/pki/usvc-users/scheduler/scheduler-key-data)

  sed -i \
    -e 's/client-certificate-data:.*/'"client-certificate-data: $ADMIN_CRT_DATA"'/' \
    -e 's/client-key-data:.*/'"client-key-data: $ADMIN_KEY_DATA"'/' \
        /etc/kubernetes/admin.conf
  sed -i \
    -e 's/client-certificate-data:.*/'"client-certificate-data: $KUBELET_CRT_DATA"'/' \
    -e 's/client-key-data:.*/'"client-key-data: $KUBELET_KEY_DATA"'/' \
        /etc/kubernetes/kubelet.conf
  sed -i \
    -e 's/client-certificate-data:.*/'"client-certificate-data: $CONTROLLER_CRT_DATA"'/' \
    -e 's/client-key-data:.*/'"client-key-data: $CONTROLLER_KEY_DATA"'/' \
        /etc/kubernetes/controller-manager.conf
  sed -i \
    -e 's/client-certificate-data:.*/'"client-certificate-data: $SCHEDULER_CRT_DATA"'/' \
    -e 's/client-key-data:.*/'"client-key-data: $SCHEDULER_KEY_DATA"'/' \
        /etc/kubernetes/scheduler.conf
}

#1.8.3 / 1.8.5 configuration
function cleanup_replace_csr_certs {
mkdir -p /etc/kubernetes/pki/usvc-backup-certs/tmp
cp -p /var/lib/kubelet/pki/* /etc/kubernetes/pki/usvc-backup-certs/tmp
cd /var/lib/kubelet/pki
rm -f *
mv /etc/kubernetes/pki/*.csr /etc/kubernetes/pki/usvc-backup-certs
mkdir -p /etc/kubernetes/pki/usvc-users/var-kubelet

cat <<-'EOF_kubepem-ext' > /etc/kubernetes/pki/usvc-users/kubepem-ext.cnf
 [ v3_ca ]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
basicConstraints = critical, CA:FALSE
subjectKeyIdentifier=hash
EOF_kubepem-ext

cd /etc/kubernetes/pki/usvc-users/var-kubelet
openssl ecparam -genkey -out kubelet.pem -name prime256v1
openssl req -new -key kubelet.pem -out kubelet-pem.csr -subj "/O=system:nodes/CN=system:node:$MASTER_HOSTNAME"
openssl x509 -req -in kubelet-pem.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -sha256 -out kubelet-client-forever.pem -extensions v3_ca -extfile /etc/kubernetes/pki/usvc-users/kubepem-ext.cnf -days 3650
cat kubelet.pem >> kubelet-client-forever.pem
sed -i -e '17,19d' /etc/kubernetes/pki/usvc-users/var-kubelet/kubelet-client-forever.pem

cd /var/lib/kubelet/pki
cp -p /etc/kubernetes/pki/usvc-users/var-kubelet/kubelet-client-forever.pem /var/lib/kubelet/pki
cp -p /etc/kubernetes/pki/usvc-users/kubelet/kubelet.crt /var/lib/kubelet/pki
cp -p /etc/kubernetes/pki/usvc-users/kubelet/kubelet.key /var/lib/kubelet/pki
ln -s kubelet-client-forever.pem kubelet-client-current.pem
}

function start_kubelet {
 systemctl start kubelet
 sleep 15
 systemctl status kubelet
}

##
# Start
cat <<-EOF_start
##
# Script:   $0
# Started:  $(date '+%T %D')
##

EOF_start

stop_kubelet
create_directories
backup_certificates
configure_v3_ca_certs
generate_certificates
configure_conf_files
cleanup_replace_csr_certs
start_kubelet

##
# Done
cat <<-EOF_end

##
# Script:   $0
# End:      $(date '+%T %D')
##
EOF_end
