
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
    version: v1
  ports:
  - port: 8080
    targetPort: 8080
EOF

  depends_on = [kubectl_manifest.apps_namespace]
}


resource "kubectl_manifest" "canary_service" {
  yaml_body = <<EOF

apiVersion: v1
kind: Service
metadata:
  name: web-2
  namespace: app-space
spec:
  selector:
    app: web
    version: v2
  ports:
  - port: 8080
    targetPort: 8080

EOF

}