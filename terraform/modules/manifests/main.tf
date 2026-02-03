terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12.0"
    }

    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
    }
  }
}

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
# STORAGE CLASSES
############################################
resource "kubectl_manifest" "mongo_storageclass" {
  yaml_body = <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: mongo-gp3
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: gp3
  encrypted: "true"
  
EOF
}

resource "kubectl_manifest" "mysql_storageclass" {
  yaml_body = <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: mysql-gp3
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: gp3
  encrypted: "true"
  
EOF
}

resource "kubectl_manifest" "storageclass_redis" {
  yaml_body = <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: redis-gp3
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: gp3
  encrypted: "true"
  
EOF
}

############################################
# SECRETS / CONFIGMAPS   
############################################
####Temporary mysql secret will use Vault injection
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
# DATA-SPACE SERVICES (separate)
############################################
resource "kubectl_manifest" "mongo_service" {
  yaml_body = <<EOF
apiVersion: v1
kind: Service
metadata:
  name: mongo
  namespace: data-space
spec:
  type: ClusterIP
  selector:
    app: mongo
  ports:
  - port: 27017
    targetPort: 27017
EOF

  depends_on = [kubectl_manifest.db_namespace]
}

resource "kubectl_manifest" "mysql_service" {
  yaml_body = <<EOF
apiVersion: v1
kind: Service
metadata:
  name: mysql
  namespace: app-space    
spec:
  selector:
    app: mysql
  ports:
  - port: 3306
    targetPort: 3306
EOF

  depends_on = [kubectl_manifest.db_namespace]
}

resource "kubectl_manifest" "redis_service" {
  yaml_body = <<EOF
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: data-space
spec:
  type: ClusterIP
  selector:
    app: redis
  ports:
  - port: 6379
    targetPort: 6379
EOF

  depends_on = [kubectl_manifest.db_namespace]
}

resource "kubectl_manifest" "rabbitmq_service" {
  yaml_body = <<EOF
apiVersion: v1
kind: Service
metadata:
  name: rabbitmq
  namespace: data-space
spec:
  selector:
    app: rabbitmq
  ports:
    - name: amqp
      port: 5672
      targetPort: 5672
EOF
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

##Add Vault mysql injection here
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

############################################
# APP-SPACE SERVICES (separate)
############################################
resource "kubectl_manifest" "cart_service" {
  yaml_body = <<EOF
apiVersion: v1
kind: Service
metadata:
  name: cart
  namespace: app-space
spec:
  selector:
    app: cart
  ports:
  - port: 8080
    targetPort: 8080
EOF

  depends_on = [kubectl_manifest.apps_namespace]
}

resource "kubectl_manifest" "catalogue_service" {
  yaml_body = <<EOF
apiVersion: v1
kind: Service
metadata:
  name: catalogue
  namespace: app-space
spec:
  selector:
    app: catalogue
  ports:
  - port: 8080
    targetPort: 8080
EOF

  depends_on = [kubectl_manifest.apps_namespace]
}

resource "kubectl_manifest" "dispatch_service" {
  yaml_body = <<EOF
apiVersion: v1
kind: Service
metadata:
  name: dispatch
  namespace: app-space
spec:
  selector:
    app: dispatch
  ports:
  - port: 80
    targetPort: 80
EOF

  depends_on = [kubectl_manifest.apps_namespace]
}

resource "kubectl_manifest" "payment_service" {
  yaml_body = <<EOF
apiVersion: v1
kind: Service
metadata:
  name: payment
  namespace: app-space
spec:
  selector:
    app: robotshop-payment 
  ports:
  - port: 8080
    targetPort: 8080
EOF

  depends_on = [kubectl_manifest.apps_namespace]
}

resource "kubectl_manifest" "ratings_service" {
  yaml_body = <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ratings
  namespace: app-space
spec:
  selector:
    app: robotshop-ratings
  ports:
  - port: 80
    targetPort: 80
EOF

  depends_on = [kubectl_manifest.apps_namespace]
}

resource "kubectl_manifest" "shipping_service" {
  yaml_body = <<EOF
apiVersion: v1
kind: Service
metadata:
  name: shipping
  namespace: app-space
spec:
  selector:
    app: shipping
  ports:
  - port: 8080
    targetPort: 8080
EOF

}



resource "kubectl_manifest" "user_service" {
  yaml_body = <<EOF
apiVersion: v1
kind: Service
metadata:
  name: user
  namespace: app-space
spec:
  selector:
    app: user
  ports:
  - port: 8080
    targetPort: 8080
EOF

  depends_on = [kubectl_manifest.apps_namespace]
}

resource "kubectl_manifest" "web_service" {
  yaml_body = <<EOF
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: app-space
spec:
  selector:
    app: web
  ports:
  - port: 8080
    targetPort: 8080
EOF

  depends_on = [kubectl_manifest.apps_namespace]
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
  template:
    metadata:
      labels:
        app: web
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
          image: 038774803581.dkr.ecr.eu-west-2.amazonaws.com/web:v5
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

##Pod Autoscaling

##Horizontal Pod Autoscaler for web traffic
#resource "kubectl_manifest" "pod_autoscaler_web" {
  #yaml_body = <<EOF
#apiVersion: autoscaling/v2
#kind: HorizontalPodAutoscaler
#metadata:
  #name: web-hpa
 # namespace: app-space
 # labels:
   # app: web
#spec:
  #scaleTargetRef:
   # apiVersion: apps/v1
   ## kind: Deployment
    #name: web

 # minReplicas: 3
 # maxReplicas: 10

 # metrics:
   # - type: Resource
   #   resource:
      #  name: cpu
      #  target:
       #   type: Utilization
       #   averageUtilization: 70

 # behavior:
   # scaleUp:
      #stabilizationWindowSeconds: 0
      #selectPolicy: Max
     # policies:
      #  - type: Percent
       #   value: 100
       #   periodSeconds: 15
       # - type: Pods
       #   value: 4
        #  periodSeconds: 15

    #scaleDown:
    #  stabilizationWindowSeconds: 300
     # policies:
      #  - type: Percent
     ##     value: 50
       #   periodSeconds: 60
#EOF
#}


##Horizontal Pod Autoscaler for User
#resource "kubectl_manifest" "pod_autoscaler_user" {
  #yaml_body = <<EOF
#apiVersion: autoscaling/v2
#kind: HorizontalPodAutoscaler
#metadata:
 # name: user-hpa
 # namespace: data-space
 # labels:
 #   app: user
#spec:
 # scaleTargetRef:
  #  apiVersion: apps/v1
   # kind: Deployment
   # name: user

  #minReplicas: 3
 # maxReplicas: 10

  #metrics:
  #  - type: Resource
    #  resource:
     #   name: cpu
     #   target:
       #   type: Utilization
       #   averageUtilization: 70

 # behavior:
   # scaleUp:
     # stabilizationWindowSeconds: 0
     # selectPolicy: Max
     # policies:
      #  - type: Percent
        #  value: 100
        #  periodSeconds: 15
       # - type: Pods
        #  value: 4
        #  periodSeconds: 15

    #scaleDown:
      #stabilizationWindowSeconds: 300
     # policies:
       # - type: Percent
        #  value: 50
        #  periodSeconds: 60
#EOF
#}




# RobotShop Web Ingress

resource "kubectl_manifest" "robotshop_web_ingress" {
  yaml_body = <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: robotshop-web
  namespace: app-space
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-staging
    nginx.ingress.kubernetes.io/proxy-set-headers: "ingress-nginx/custom-headers"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - mubashir.site
      secretName: mubashir-site-tls
  rules:
    - host: mubashir.site
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web
                port:
                  number: 8080
EOF
}



resource "kubectl_manifest" "configmap-https" {
  yaml_body = <<EOF

apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-headers
  namespace: ingress-nginx
data:
  X-Forwarded-Proto: "https"

EOF
}


resource "kubectl_manifest" "robotshop_config" {
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


##RBAC

resource "kubectl_manifest" "vault_auth_crb" {
  yaml_body = <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-auth-delegator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: vault-auth
  namespace: kube-system
EOF

  depends_on = [kubectl_manifest.vault_auth_sa]
}

##Service Accounts

resource "kubectl_manifest" "vault_auth_sa" {
  yaml_body = <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-auth
  namespace: kube-system
EOF
}

#Cart Service Account
resource "kubectl_manifest" "cart_sa" {
  yaml_body = <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cart-sa
  namespace: app-space
EOF
}

#Catalogue Service Account
resource "kubectl_manifest" "catalogue_sa" {
  yaml_body = <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: catalogue-sa
  namespace: app-space
EOF
}

#Shipping Service Account
resource "kubectl_manifest" "shipping_sa" {
  yaml_body = <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: shipping-sa
  namespace: app-space
EOF
}

#Web Service Account
resource "kubectl_manifest" "web_sa" {
  yaml_body = <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: web-sa
  namespace: app-space
EOF
}

#Payment Service Account
resource "kubectl_manifest" "payment_sa" {
  yaml_body = <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: payment-sa
  namespace: app-space
EOF
}


#Ratings Service Account
resource "kubectl_manifest" "ratings_sa" {
  yaml_body = <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ratings-sa
  namespace: app-space
EOF
}

#User Service Account
resource "kubectl_manifest" "user_sa" {
  yaml_body = <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: user-sa
  namespace: app-space
EOF
}

###Each microservice runs under its own Kubernetes 
#ServiceAccount, which Vault uses as the 
#workload identity to issue a short-lived Vault token
#mapped to a least-privilege policy. 
#This prevents lateral secret access between services



