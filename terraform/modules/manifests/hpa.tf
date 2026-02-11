##Horizontal Pod Autoscaler for web traffic
resource "kubectl_manifest" "pod_autoscaler_web" {
  yaml_body = <<EOF
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: web-hpa
  namespace: app-space
  labels:
    app: web
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web

  minReplicas: 3
  maxReplicas: 10

  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70

  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
      selectPolicy: Max
      policies:
        - type: Percent
          value: 100
          periodSeconds: 15
        - type: Pods
          value: 4
          periodSeconds: 15

    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Percent
          value: 50
          periodSeconds: 60
EOF
}


#Horizontal Pod Autoscaler for User
resource "kubectl_manifest" "pod_autoscaler_user" {
  yaml_body = <<EOF
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: user-hpa
  namespace: data-space
  labels:
    app: user
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: user

  minReplicas: 3
  maxReplicas: 10

  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70

  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
      selectPolicy: Max
      policies:
        - type: Percent
          value: 100
          periodSeconds: 15
        - type: Pods
          value: 4
          periodSeconds: 15

    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Percent
          value: 50
          periodSeconds: 60
EOF
}

