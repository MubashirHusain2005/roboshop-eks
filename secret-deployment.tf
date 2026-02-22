resource "kubectl_manifest" "mysql_statefulset" {
  yaml_body = <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
  namespace: app-space   
spec:
  serviceName: mysql
  replicas: 1
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
        - name: mysql
          image: 038774803581.dkr.ecr.eu-west-2.amazonaws.com/mysql:v1
          ports:
            - containerPort: 3306
              name: mysql
          env:
            - name: MYSQL_DATABASE
              value: cities
            - name: MYSQL_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mysql-secret
                  key: root-password
            - name: MYSQL_USER
              value: shipping
            - name: MYSQL_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mysql-secret
                  key: user-password
          resources:
            requests:
              cpu: "100m"
              memory: "256Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
          volumeMounts:
            - name: mysql-data
              mountPath: /var/lib/mysql
              subPath: mysql
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - |
                  mysqladmin ping \
                    -h 127.0.0.1 \
                    -u root \
                    -p"$MYSQL_ROOT_PASSWORD" \
                    --silent
            initialDelaySeconds: 30
            periodSeconds: 10

  volumeClaimTemplates:
    - metadata:
        name: mysql-data
      spec:
        accessModes:
          - ReadWriteOnce
        storageClassName: mysql-gp3
        resources:
          requests:
            storage: 5Gi
EOF


  depends_on = [
    kubectl_manifest.mysql_secret,
    kubectl_manifest.mysql_storageclass,
    kubectl_manifest.resource_quota_dataspace
  ]
}


resource "kubectl_manifest" "deployment_shipping" {
  yaml_body = <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: robotshop-shipping
  namespace: app-space
spec:
  replicas: 1
  selector:
    matchLabels:
      app: shipping
  template:
    metadata:
      labels:
        app: shipping
    spec:
      serviceAccountName: shipping-sa
      containers:
        - name: robot-app-shipping
          image: 038774803581.dkr.ecr.eu-west-2.amazonaws.com/shipping:v1
          imagePullPolicy: Always
          env:
            - name: DB_HOST
              value: mysql
            - name: DB_PORT
              value: "3306"
            - name: DB_USER
              valueFrom:
                secretKeyRef:
                  name: db-creds
                  key: DB_USER
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: db-creds
                  key: DB_PASSWORD
          volumeMounts:
            - name: secrets-store
              mountPath: /mnt/secrets
              readOnly: true
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: "250m"
              memory: "512Mi"
            limits:
              cpu: "500m"
              memory: "1Gi"
          startupProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 60
            periodSeconds: 10
            failureThreshold: 18
            
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 60
            periodSeconds: 10
            failureThreshold: 6

          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 120
            periodSeconds: 20
            failureThreshold: 3

      volumes:
        - name: secrets-store
          csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes:
              secretProviderClass: db-secrets

EOF

  depends_on = [
    kubectl_manifest.mysql_statefulset,
    kubectl_manifest.shipping_sa,
    aws_secretsmanager_secret_version.secrets,
    aws_secretsmanager_secret.secrets

  ]
}


####OLD SHIPPING STATEFULSET:WORKING

resource "kubectl_manifest" "deployment_shipping" {
  yaml_body = <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: robotshop-shipping
  namespace: app-space
spec:
  replicas: 1
  selector:
    matchLabels:
      app: shipping
  template:
    metadata:
      labels:
        app: shipping
    spec:
      serviceAccountName: shipping-sa
      containers:
        - name: robot-app-shipping
          image: 038774803581.dkr.ecr.eu-west-2.amazonaws.com/shipping:v1
          imagePullPolicy: Always
          env:
            - name: DB_HOST
              value: mysql
            - name: DB_PORT
              value: "3306"
            - name: DB_USER
              value: shipping
            - name: DB_PASSWORD
              value: secret
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: "250m"
              memory: "512Mi"
            limits:
              cpu: "500m"
              memory: "1Gi"

          startupProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 60
            periodSeconds: 10
            failureThreshold: 18

          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 60
            periodSeconds: 10
            failureThreshold: 6

          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 120
            periodSeconds: 20
            failureThreshold: 3

EOF

  depends_on = [
    kubectl_manifest.mysql_statefulset,
    kubectl_manifest.shipping_sa
  ]
}



aws secretsmanager delete-secret \
>   --secret-id db-creds \
>   --force-delete-without-recovery




resource "kubectl_manifest" "web_service_monitor" {
    yaml_body = <<EOF

apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: robotshop-servicemonitor
  namespace: monitoring
  selector:
    matchLabels:
      app: web
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
  namespaceSelector:
    matchNames:
        - app-space

EOF
}

resource "kubectl_manifest" "user_service_monitor" {
    yaml_body = <<EOF

apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: robotshop-servicemonitor
  namespace: monitoring
  selector:
    matchLabels:
      app: user
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
  namespaceSelector:
    matchNames:
        - app-space

EOF
}

resource "kubectl_manifest" "payment_service_monitor" {
    yaml_body = <<EOF

apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: robotshop-servicemonitor
  namespace: monitoring
  selector:
    matchLabels:
      app: payment
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
  namespaceSelector:
    matchNames:
        - app-space

EOF
}

resource "kubectl_manifest" "shipping_service_monitor" {
    yaml_body = <<EOF

apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: robotshop-servicemonitor
  namespace: monitoring
  selector:
    matchLabels:
      app: shipping
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
  namespaceSelector:
    matchNames:
        - app-space
EOF
}

##Pod Monitors to scrape metrics for databases