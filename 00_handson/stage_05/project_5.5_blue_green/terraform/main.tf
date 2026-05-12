# Blue-green deployment uses existing AKS cluster from project 5.4
# Apply k8s manifests directly with kubectl

# blue-deployment.yaml (create manually):
# apiVersion: apps/v1
# kind: Deployment
# metadata:
#   name: myapp-blue
# spec:
#   replicas: 2
#   selector:
#     matchLabels: {app: myapp, version: blue}
#   template:
#     metadata:
#       labels: {app: myapp, version: blue}
#     spec:
#       containers:
#         - name: myapp
#           image: acrhandson001.azurecr.io/myapp:v1.0

# Service selector switches between blue/green:
# kubectl patch service myapp-svc -p '{"spec":{"selector":{"version":"blue"}}}'
# kubectl patch service myapp-svc -p '{"spec":{"selector":{"version":"green"}}}'
