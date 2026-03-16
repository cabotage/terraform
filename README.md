```
minikube start --cpus 6 --memory 16000 --cni calico --container-runtime containerd
minikube addons enable ingress-dns
minikube addons enable registry
cd clusters/minikube/cabotage
terraform init -upgrade
terraform apply
```
