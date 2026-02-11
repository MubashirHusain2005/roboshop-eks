
############################################
# NAMESPACES
############################################
resource "kubectl_manifest" "apps_namespace" {
  yaml_body = <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: app-space
EOF
}

resource "kubectl_manifest" "db_namespace" {
  yaml_body = <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: data-space
EOF
}

############################################
# RESOURCE QUOTAS
############################################
resource "kubectl_manifest" "resource_quota_appspace" {
  yaml_body = <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: app-quota
  namespace: app-space
spec:
  hard:
    requests.cpu: "4"
    requests.memory: "4Gi"
    limits.cpu: "8"
    limits.memory: "8Gi"
    pods: "30"
EOF

  depends_on = [kubectl_manifest.apps_namespace]
}

resource "kubectl_manifest" "resource_quota_dataspace" {
  yaml_body = <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: data-quota
  namespace: data-space
spec:
  hard:
    requests.cpu: "4"
    requests.memory: "8Gi"
    limits.cpu: "8"
    limits.memory: "16Gi"
    pods: "15"
EOF

  depends_on = [kubectl_manifest.db_namespace]
}

############################################
# SECRETS / CONFIGMAPS   
############################################

resource "kubectl_manifest" "mysql_secret" {
  yaml_body = <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: mysql-secret
  namespace: app-space    
type: Opaque
stringData:
  root-password: rootpass
  user-password: secret
EOF

  depends_on = [kubectl_manifest.db_namespace]
}

resource "kubectl_manifest" "redis_configmap" {
  yaml_body = <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-config
  namespace: data-space 
  
data:
  redis.conf: |
    appendonly yes
    appendfsync everysec
EOF

  depends_on = [kubectl_manifest.db_namespace]
}


############################################
# DATA-SPACE STATEFULSETS / DEPLOYMENTS
############################################


resource "kubectl_manifest" "mongo_statefulset" {
  yaml_body = <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mongo
  namespace: data-space
spec:
  serviceName: mongo
  replicas: 1
  selector:
    matchLabels:
      app: mongo
  template:
    metadata:
      labels:
        app: mongo
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: workload
                operator: In
                values:
                - database
      containers:
      - name: mongo
        image: 038774803581.dkr.ecr.eu-west-2.amazonaws.com/mongo:v1
        ports:
        - containerPort: 27017
        volumeMounts:
        - name: mongo-data
          mountPath: /data/db
        resources:
          requests:
            cpu: "100m"
            memory: "256Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
  volumeClaimTemplates:
  - metadata:
      name: mongo-data
    spec:
      accessModes:
      - ReadWriteOnce
      storageClassName: mongo-gp3
      resources:
        requests:
          storage: 5Gi
EOF

  depends_on = [
    kubectl_manifest.mongo_service,
    kubectl_manifest.mongo_storageclass,
    kubectl_manifest.resource_quota_dataspace
  ]
}

##
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

resource "kubectl_manifest" "redis_statefulset" {
  yaml_body = <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
  namespace: data-space
spec:
  serviceName: redis
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: workload
                operator: In
                values:
                - database
      containers:
      - name: redis
        image: redis:6.2-alpine
        resources:
          requests:
            cpu: "100m"
            memory: "256Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
        volumeMounts:
        - name: redis-data
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: redis-data
    spec:
      accessModes:
      - ReadWriteOnce
      storageClassName: redis-gp3
      resources:
        requests:
          storage: 10Gi
EOF

  depends_on = [
    kubectl_manifest.redis_service,
    kubectl_manifest.storageclass_redis,
    kubectl_manifest.redis_configmap,
    kubectl_manifest.resource_quota_dataspace
  ]
}

resource "kubectl_manifest" "rabbitmq_deployment" {
  yaml_body = <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rabbitmq
  namespace: data-space
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rabbitmq
  template:
    metadata:
      labels:
        app: rabbitmq
    spec:
      containers:
      - name: rabbitmq
        image: rabbitmq:3.8-management-alpine
        ports:
        - containerPort: 5672
        env:
          - name: RABBITMQ_DEFAULT_USER
            value: guest
          - name: RABBITMQ_DEFAULT_PASS
            value: guest
          - name: RABBITMQ_ALLOW_GUEST
            value: "true"
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "256Mi"
EOF

  depends_on = [
    kubectl_manifest.rabbitmq_service,
    kubectl_manifest.resource_quota_dataspace
  ]
}



# APP-SPACE DEPLOYMENTS 

resource "kubectl_manifest" "deployment_cart" {
  yaml_body = <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: robotshop-cart
  namespace: app-space
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cart
  template:
    metadata:
      labels:
        app: cart
    spec:
      containers:
      - name: robot-app-cart
        image: 038774803581.dkr.ecr.eu-west-2.amazonaws.com/cart:v1
        imagePullPolicy: Always
        ports:
        - containerPort: 8080
        env:
        - name: REDIS_HOST
          value: redis.data-space.svc.cluster.local
        - name: REDIS_PORT
          value: "6379"
        - name: CATALOGUE_HOST
          value: catalogue.app-space.svc.cluster.local
        - name: INSTANA_DISABLE_AUTP_INSTR
          value: "true"
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "256Mi"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
EOF

  depends_on = [
    kubectl_manifest.cart_service,
    kubectl_manifest.resource_quota_appspace
  ]
}

resource "kubectl_manifest" "deployment_catalogue" {
  yaml_body = <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: robotshop-catalogue
  namespace: app-space
spec:
  replicas: 1
  selector:
    matchLabels:
      app: catalogue
  template:
    metadata:
      labels:
        app: catalogue
    spec:
      containers:
      - name: robot-app-catalogue
        image: 038774803581.dkr.ecr.eu-west-2.amazonaws.com/catalogue:v1
        imagePullPolicy: Always
        ports:
        - containerPort: 8080
        env:
        - name: MONGO_URL
          value: mongodb://mongo.data-space.svc.cluster.local:27017/catalogue
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "256Mi"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
EOF

  depends_on = [
    kubectl_manifest.catalogue_service,
    kubectl_manifest.resource_quota_appspace
  ]
}

resource "kubectl_manifest" "deployment_dispatch" {
  yaml_body = <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: robotshop-dispatch
  namespace: app-space
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dispatch
  template:
    metadata:
      labels:
        app: dispatch
    spec:
      containers:
      - name: robot-app-dispatch
        image: 038774803581.dkr.ecr.eu-west-2.amazonaws.com/dispatch:v1
        imagePullPolicy: Always
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "256Mi"
EOF

  depends_on = [
    kubectl_manifest.dispatch_service,
    kubectl_manifest.resource_quota_appspace
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
      containers:
        - name: robot-app-shipping
          image: 038774803581.dkr.ecr.eu-west-2.amazonaws.com/shipping:v1
          imagePullPolicy: Always
          envFrom:
            - secretRef:
                name: kube-secret
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
    kubernetes_service_account_v1.eso_serviceaact,
   kubernetes_manifest.external_secret,
   #kubernetes_manifest.secret_store
  ]
}

resource "kubectl_manifest" "deployment_payment" {
  yaml_body = <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: robotshop-payment
  namespace: app-space
spec:
  replicas: 1
  selector:
    matchLabels:
      app: robotshop-payment
  template:
    metadata:
      labels:
        app: robotshop-payment
    spec:
      containers:
      - name: robot-app-payment
        image: 038774803581.dkr.ecr.eu-west-2.amazonaws.com/payment:v1
        imagePullPolicy: Always
        ports:
        - containerPort: 8080
        env:
          - name: AMQP_HOST
            value: rabbitmq.data-space.svc.cluster.local
          - name: AMQP_PORT
            value: "5672"
          - name: RABBITMQ_PASSWORD
            value: guest
          - name: RABBITMQ_USER
            value: guest
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "256Mi"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
EOF

  depends_on = [
    kubectl_manifest.payment_service,
    kubectl_manifest.resource_quota_appspace
  ]
}


resource "kubectl_manifest" "deployment_ratings" {
  yaml_body = <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: robotshop-ratings
  namespace: app-space
spec:
  replicas: 1
  selector:
    matchLabels:
      app: robotshop-ratings
  template:
    metadata:
      labels:
        app: robotshop-ratings
    spec:
      containers:
      - name: robot-app-ratings
        image: 038774803581.dkr.ecr.eu-west-2.amazonaws.com/ratings:v1
        imagePullPolicy: Always
        ports:
        - containerPort: 80
        env:
          - name: MONGO_HOST
            value: mongo.data-space.svc.cluster.local
          - name: MONGO_PORT
            value: "27017"
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "256Mi"
EOF

  depends_on = [
    kubectl_manifest.ratings_service,
    kubectl_manifest.resource_quota_appspace
  ]
}


resource "kubectl_manifest" "deployment_user" {
  yaml_body = <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: robotshop-user
  namespace: app-space
spec:
  replicas: 1
  selector:
    matchLabels:
      app: user
  template:
    metadata:
      labels:
        app: user
    spec:
      containers:
      - name: robot-app-user
        image: 038774803581.dkr.ecr.eu-west-2.amazonaws.com/user:v1
        imagePullPolicy: Always
        ports:
        - containerPort: 8080
        env:
          - name: TRUST_PROXY
            value: "true"
          - name: INSTANA_DISABLE_AUTO_INSTR
            value: "true"
          - name: REDIS_HOST
            value: redis.data-space.svc.cluster.local
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "256Mi"
EOF

  depends_on = [
    kubectl_manifest.user_service,
    kubectl_manifest.resource_quota_appspace
  ]
}

resource "kubectl_manifest" "deployment_web" {
  yaml_body = <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: app-space
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web
      version: v1
  template:
    metadata:
      labels:
        app: web
        version: v1
    spec:
      containers:
        # ===============================
        # NGINX FRONT PROXY (SIDE CAR)
        # ===============================
        - name: web-nginx
          image: nginx:1.21.6
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: "50m"
              memory: "50Mi"
            limits:
              cpu: "100m"
              memory: "100Mi"
          volumeMounts:
            - name: nginx-config
              mountPath: /etc/nginx/conf.d


        # ===============================
        # EXISTING WEB CONTAINER
        # ===============================
        - name: robot-app-web
          image: 038774803581.dkr.ecr.eu-west-2.amazonaws.com/web:v1
          imagePullPolicy: Always
          ports:
            - containerPort: 3000
          env:
            - name: SESSION_SECURE
              value: "false"
            - name: SESSION_SAMESITE
              value: "lax"
            - name: INSTANA_DISABLE_AUTO_INSTR
              value: "true"
          resources:
            requests:
              cpu: "100m"
              memory: "60Mi"
            limits:
              cpu: "200m"
              memory: "100Mi"

      volumes:
        - name: nginx-config
          configMap:
            name: web-nginx-config
EOF


  depends_on = [
    kubectl_manifest.web_service,
    kubectl_manifest.resource_quota_appspace,
    kubectl_manifest.mysql_statefulset

  ]
}






###IRSA for shipping pod so it can access AWS Secrets Manager

#resource "aws_iam_role" "shipping_irsa" {
#name = "iam-secrets-access"

# assume_role_policy = jsonencode({
# Version = "2012-10-17"
#  Statement = [
#  {
#   Effect = "Allow"
# Principal = {
#   Federated = "${aws_iam_openid_connect_provider.eks.arn}"
#  }
#  Action = "sts:AssumeRoleWithWebIdentity"
# Condition = {
#  StringEquals = {
#    "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:app-space:shipping_sa",
#  "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
#  }
# }
#}
#]
# })
#}


#resource "aws_iam_policy" "shipping_secrets_policy" {
# name = "shipping-secrets-manager-access"

# policy = jsonencode({
# Version = "2012-10-17"
# Statement = [
#  {
# Effect = "Allow"
# Action = [
#  "secretsmanager:GetSecretValue",
# #  "secretsmanager:DescribeSecret"
#]
# Resource = "arn:aws:secretsmanager:eu-west-2:*:secret:robotshop/shipping/*"
# }
#]
#})
#}

#resource "aws_iam_role_policy_attachment" "shipping_policy_irsa" {
# role       = aws_iam_role.shipping_irsa.name
#policy_arn = aws_iam_policy.shipping_secrets_policy.arn
#}