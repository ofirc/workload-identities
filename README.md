# Workload Identities
This repo accompanies a talk I gave in a CNCF meetup at San Francisco, Aug'24 around Kubernetes Workload Identities:
https://drive.google.com/file/d/1QigVMCYaqwizljDRklHcrsVN0AXMBNcv/view?usp=sharing

This repo demonstrates how to safely and securely access your cloud resources (e.g. AWS S3, Google Cloud Bucket) from managed Kubernetes clusters (e.g. EKS, GKE, AKS).

The repo provides blueprints for provisioning K8s clusters via:
1. [Manually provisioning clusters - through the CLI](#manual-provisioning)
2. [Automatically with Terraform (IaC)](#using-terraform)
3. [Automatically with Pulumi (IaC)](#using-pulumi)

Now while the marketing terms (e.g. Pod Identity vs Workload Identity) vary across the different cloud providers, they all refer to the same concept:
1. AWS - [EKS Pod Identities](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
2. GCP - [GKE Workload Identities](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
3. Azure - [Microsoft Entra Workload Id](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview?tabs=dotnet)

And rely on the combination of the following to obtain access to cloud assets from the K8s clusters:
* [ServiceAccount token volume projection (since v1.20 stable)](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#serviceaccount-token-volume-projection)
* [OAuth 2.0 token exchange (RFC8693)](https://datatracker.ietf.org/doc/html/rfc8693)
* A [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/) - per worker node agent/broker to cache
* A [MutatingWebhookConfiguration](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/) - for injecting the env vars onto the Pods to later be picked up by the cloud providers SDKs credential chain

What is also cool about this setup is that it allows to support use cases such as:
* Cross cloud access - e.g. from EKS to buckets on GCP
* On-prem K8s clusters to cloud - e.g. from OpenShift/Rancher to your Amazon RDS database

# Manual provisioning
## AWS EKS

**Step 1: create the cluster and enable Pod identities**
```
eksctl create cluster --name pod-identities-demo
eksctl create addon \
  --cluster pod-identities-demo \
  --name eks-pod-identity-agent
```

**Step 2: create an S3 bucket for testing the access from EKS**
```
aws s3api create-bucket \
  --bucket pod-identities-bucket \
  --create-bucket-configuration LocationConstraint=eu-north-1
echo "Hello, World\!" > hello.txt
aws s3 cp hello.txt s3://pod-identities-bucket/
aws s3 cp s3://pod-identities-bucket/hello.txt -
```

**Step 3: create the IAM Role for accessing S3**
```
aws iam create-role --role-name pod-identities-role --assume-role-policy-document '{ "Version": "2012-10-17", "Statement": [{ "Effect": "Allow", "Principal": { "Service": "pods.eks.amazonaws.com" }, "Action": ["sts:AssumeRole", "sts:TagSession"] }] }’

cat > s3-access-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": "arn:aws:s3:::pod-identities-bucket"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject"
            ],
            "Resource": "arn:aws:s3:::pod-identities-bucket/*"
        }
    ]
}
EOF

aws iam put-role-policy \
  --role-name pod-identities-role \
  --policy-name S3AccessPolicy \
  --policy-document file://s3-access-policy.json
```

**Step 4: marry the two together, a-la federated identities**
```
role_arn=$(aws iam get-role --role-name "pod-identities-role" --query 'Role.Arn' --output text)
aws eks create-pod-identity-association \
  --cluster-name pod-identities-demo \
  --namespace default \
  --service-account default \
  --role-arn $role_arn
```

**Step 5: show time, are you ready???? I can't hear ya!**

```
# Spin up an ephemeral Pod.
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: pod-identities-demo
spec:
  #serviceAccountName: default
  containers:
  - name: main
    image: public.ecr.aws/aws-cli/aws-cli
    command: ["sleep", "infinity"]
EOF
```

Access the S3 bucket from within the Pod running in the cluster:
```
kubectl exec pod/pod-identities-demo -- aws s3 cp s3://pod-identities-bucket/hello.txt -
```

If all went well, you should see the following:
```
$ kubectl exec pod/pod-identities-demo -- aws s3 cp s3://pod-identities-bucket/hello.txt -
Hello, World!
$
```

## Azure Kubernetes Services (AKS)
TBD

## Google Kubernetes Engine (GKE)
TBD


# Using Terraform
Start by installing Terraform:
```
brew install terraform
```

## AWS EKS
Prepare the Terraform environment:
```
cd terraform/eks
terraform init
terraform plan
```

If you are happy with the plan, proceed to:
```
terraform apply
```

And set the context to the newly created cluster:
```
aws eks update-kubeconfig --region eu-north-1 --name pod-identities-demo-terraform
```

Verify that the Pod Identities DaemonSet is installed:
```
$ kubectl get ds -A
NAMESPACE     NAME                     DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
kube-system   aws-node                 1         1         1       1            1           <none>          17m
kube-system   eks-pod-identity-agent   1         1         1       1            1           <none>          15m
kube-system   kube-proxy               1         1         1       1            1           <none>          17m
$
```

Verify that the AWS SDK Pod is up and running:
```
$ kubectl get pod --show-labels
NAME                                   READY   STATUS    RESTARTS   AGE     LABELS
pod-identities-demo-7899d596c4-4p794   1/1     Running   0          2m17s   app=pod-identities-demo,pod-template-hash=7899d596c4
$
```

And finally, access the S3 bucket from the Pod (using pod identities):
```
BUCKET_NAME=pod-identities-demo-terraform
POD_NAME=$(kubectl get pod -lapp=pod-identities-demo -oname)
kubectl exec $POD_NAME -- aws s3 cp s3://$BUCKET_NAME/hello.txt -
```

If all went well, you should see the following:
```
$ kubectl exec $POD_NAME -- aws s3 cp s3://$BUCKET_NAME/hello.txt -
Hello, World!%
$
```

Take a moment to pause and enjoy the excitement!

And when you are done:
```
terraform destroy
```

## Azure Kubernetes Services (AKS)
TBD

## Google Kubernetes Engine (GKE)
TBD

# Using Pulumi
Start by installing Pulumi:
```
brew install pulumi
```

And make sure to register a Pulumi account if you don't already have one.
Check out:
https://www.pulumi.com/docs/clouds/aws/get-started/

## AWS EKS
```
cd pulumi/eks
go mod tidy
pulumi stack init dev
pulumi config set aws:region eu-north-1
pulumi up
pulumi stack output
```

Ensure that you have the S3 bucket properly provisioned:
```
aws s3 ls $(pulumi stack output pod-identities-bucket-pulumi)
```

Should look like the following:
```
$ aws s3 ls $(pulumi stack output pod-identities-bucket-pulumi)
2024-08-26 00:08:19         13 hello.txt
$
```

Export the kubeconfig json:
```
pulumi stack output kubeconfig --show-secrets >kubeconfig.json
```

Verify that the Pod Identities DaemonSet is installed:
```
$ KUBECONFIG=./kubeconfig.json kubectl get ds -A
NAMESPACE     NAME                     DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
kube-system   aws-node                 2         2         2       2            2           <none>          15h
kube-system   eks-pod-identity-agent   2         2         2       2            2           <none>          15h
kube-system   kube-proxy               2         2         2       2            2           <none>          15h
$
```

Verify that the AWS SDK Pod is up and running:
```
$ KUBECONFIG=./kubeconfig.json kubectl get pod --show-labels
NAME                                               READY   STATUS    RESTARTS   AGE   LABELS
pod-identities-demo-pod-559c40c8-d6bf46c7c-529pq   1/1     Running   0          86s   app=pod-identities-demo,pod-template-hash=d6bf46c7c
$
```

And finally, access the S3 bucket from the Pod (using pod identities):
```
BUCKET_NAME=$(pulumi stack output pod-identities-bucket-pulumi)
POD_NAME=$(KUBECONFIG=./kubeconfig.json kubectl get pod -lapp=pod-identities-demo -oname)
KUBECONFIG=./kubeconfig.json kubectl exec $POD_NAME -- aws s3 cp s3://$BUCKET_NAME/hello.txt -
```

If all went well, you should see the following:
```
$ KUBECONFIG=./kubeconfig.json kubectl exec $POD_NAME -- aws s3 cp s3://$BUCKET_NAME/hello.txt -
Hello, World!
$
```

Take a moment to pause and enjoy the excitement!

And when you are done:
```
pulumi destroy
pulumi stack rm
```

## Azure Kubernetes Services (AKS)
TBD

## Google Kubernetes Engine (GKE)
TBD

