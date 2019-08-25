#!/bin/sh
# Install kubeadm

sudo swapoff -a

#check id
# ip link
# sudo cat sudo cat /sys/class/dmi/id/product_uuid


sudo -i
#Install Docker CE
## Set up the repository:
### Install packages to allow apt to use a repository over HTTPS
apt-get update && apt-get install apt-transport-https ca-certificates curl software-properties-common

### Add Docker’s official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -

### Add Docker apt repository.
add-apt-repository \
  "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) \
  stable"

## Install Docker CE.
apt-get update && apt-get install docker-ce

# Setup daemon.
cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

mkdir -p /etc/systemd/system/docker.service.d

# Restart docker.
systemctl daemon-reload
systemctl restart docker

# Install kubeadm kubelet kubectl
apt-get update && apt-get install -y apt-transport-https curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
# init kubeadm
# docker version not support!
kubeadm init --pod-network-cidr=10.244.0.0/16

# add other terminal
mkdir -p $HOME/.kube
cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

export KUBECONFIG=/etc/kubernetes/admin.conf# ???

# cat /proc/sys/net/bridge/bridge-nf-call-iptables 
# check "1"
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/62e44c867a2846fefb68bd5f178daf4da3095ccb/Documentation/kube-flannel.yml

kubectl taint nodes --all node-role.kubernetes.io/master-
# ?

# install helm
sudo snap install helm --classic
helm init --history-max 200
# install istio
export ISTIO_VERSION=1.1.7
curl -L https://git.io/getLatestIstio | sh -
cd istio-${ISTIO_VERSION}
for i in install/kubernetes/helm/istio-init/files/crd*yaml; do kubectl apply -f $i; done


cat <<EOF | kubectl apply -f -
   apiVersion: v1
   kind: Namespace
   metadata:
     name: istio-system
     labels:
       istio-injection: disabled
EOF


# A lighter template, with just pilot/gateway.
# Based on install/kubernetes/helm/istio/values-istio-minimal.yaml
helm template --namespace=istio-system \
  --set prometheus.enabled=false \
  --set mixer.enabled=false \
  --set mixer.policy.enabled=false \
  --set mixer.telemetry.enabled=false \
  `# Pilot does not need a sidecar.`\
  --set pilot.sidecar=false \
  --set pilot.resources.requests.memory=128Mi \
  `# Disable galley (and things requiring galley).` \
  --set galley.enabled=false \
  --set global.useMCP=false \
  `# Disable security / policy.` \
  --set security.enabled=false \
  --set global.disablePolicyChecks=true \
  `# Disable sidecar injection.` \
  --set sidecarInjectorWebhook.enabled=false \
  --set global.proxy.autoInject=disabled \
  --set global.omitSidecarInjectorConfigMap=true \
  `# Set gateway pods to 1 to sidestep eventual consistency / readiness problems.` \
  --set gateways.istio-ingressgateway.autoscaleMin=1 \
  --set gateways.istio-ingressgateway.autoscaleMax=1 \
  `# Set pilot trace sampling to 100%` \
  --set pilot.traceSampling=100 \
  install/kubernetes/helm/istio \
  > ./istio-lean.yaml

kubectl apply -f istio-lean.yaml

# from https://github.com/helm/helm/issues/4181
kubectl taint nodes --all node-role.kubernetes.io/master-

# Add the extra gateway.
helm template --namespace=istio-system \
  --set gateways.custom-gateway.autoscaleMin=1 \
  --set gateways.custom-gateway.autoscaleMax=1 \
  --set gateways.custom-gateway.cpu.targetAverageUtilization=60 \
  --set gateways.custom-gateway.labels.app='cluster-local-gateway' \
  --set gateways.custom-gateway.labels.istio='cluster-local-gateway' \
  --set gateways.custom-gateway.type='ClusterIP' \
  --set gateways.istio-ingressgateway.enabled=false \
  --set gateways.istio-egressgateway.enabled=false \
  --set gateways.istio-ilbgateway.enabled=false \
  install/kubernetes/helm/istio \
  -f install/kubernetes/helm/istio/example-values/values-istio-gateways.yaml \
  | sed -e "s/custom-gateway/cluster-local-gateway/g" -e "s/customgateway/clusterlocalgateway/g" \
  > ./istio-local-gateway.yaml

kubectl apply -f istio-local-gateway.yaml

# cleanup knative
kubectl delete svc knative-ingressgateway -n istio-system
kubectl delete deploy knative-ingressgateway -n istio-system
kubectl delete statefulset/controller-manager -n knative-sources

# prevents race conditions 
kubectl apply --selector knative.dev/crd-install=true \
   --filename https://github.com/knative/serving/releases/download/v0.8.0/serving.yaml \
   --filename https://github.com/knative/eventing/releases/download/v0.8.0/eventing.yaml \
   --filename https://github.com/knative/serving/releases/download/v0.8.0/monitoring.yaml
# install knative
kubectl apply --filename https://github.com/knative/serving/releases/download/v0.8.0/serving.yaml \
   --filename https://github.com/knative/eventing/releases/download/v0.8.0/eventing.yaml \
   --filename https://github.com/knative/serving/releases/download/v0.8.0/monitoring.yaml

# add other terminal
mkdir -p $HOME/.kube
cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
