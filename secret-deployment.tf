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


##resource "kubectl_manifest" "robotshop_config" {
  yaml_body = <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: web-nginx-config
  namespace: app-space
data:
  default.conf: |
    server {
      listen 8080;

        proxy_http_version 1.1;

        root /usr/share/nginx/html;
        index index.html;

        location ^~ /api/catalogue/ {
            proxy_pass http://catalogue:8080/;
        }

        location ^~ /api/user/ {
            proxy_pass http://user:8080/;
        }

        location ^~ /api/cart/ {
            proxy_pass http://cart:8080/;
        }

        location ^~ /api/shipping/ {
            rewrite ^/api/shipping/?(.*)$ /$1 break;
            proxy_pass http://shipping:8080/shipping/;
        }

        location ^~ /api/payment/ {
            rewrite ^/api/payment/?(.*)$ /$1 break;
            proxy_pass http://payment:8080/payment/;
        }

        location ^~ /api/ratings/ {
            proxy_pass http://ratings:80/;
        }

        location / {
             proxy_pass http://127.0.0.1:3000;
             proxy_set_header Host $host;
             proxy_set_header X-Real-IP $remote_addr;
             proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
             proxy_set_header X-Forwarded-Proto $scheme;
        }

        # ===============================
        # STATIC FILES
        # ===============================
        location /images/ {
            proxy_pass http://127.0.0.1:3000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            }
    }
EOF
}