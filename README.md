# Workload Identities
This repo demonstrates how to safely and securely access your cloud resources (e.g. AWS S3, Google Cloud Bucket) from managed Kubernetes clusters.

The repo provides blueprints for provisioning clusters using either:
1. Manually provisioning clusters - through the CLI
2. Automatically with Terraform (IaC)
3. Automatically with Pulumi (IaC)

While the marketing varies across the different cloud providers, they all refer to the same concept:
1. GCP - [GKE Workload Identities](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
2. Azure - [Microsoft Entra Workload Id](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview?tabs=dotnet)
3. AWS - [EKS Pod Identities](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)

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
## AWS EKS
TBD

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

