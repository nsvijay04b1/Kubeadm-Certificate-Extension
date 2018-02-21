<b>Certificate Script to generate k8s cert</b>

Bootstrapping a cluster with kubeadm generates certificates with a duration of one year, because upgrading a cluster to newer versions does not refresh the duration I've created this bash script to generate certificate for 10 years and put them in the default admin, kubelet, scheduler and controller-manager conf files.
With the first run it will back-up the existing certificates into the specified folder.

Make sure to fill in the variables before executing the script else this will cause the kubelet on master to fail to communicate with the API server.

